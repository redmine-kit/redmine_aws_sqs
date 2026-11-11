# frozen_string_literal: true

require_relative '../test_helper'

class RedmineAwsSqsTestJob < ActiveJob::Base
  cattr_accessor :runs, default: 0

  def perform(fail)
    self.class.runs += 1
    raise ArgumentError, 'the job failed' if fail
  end
end

module RedmineAws
  module SQS
    # aws-activejob-sqs's handler with the plugin's patch, on SDK response stubs.
    class LambdaHandlerPatchTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def setup
        RedmineAwsSqsTestJob.runs = 0
      end

      def handle(body, receives:, dead_letter: true)
        with_queue_url(QUEUE_URL) do
          RedmineAws::SQS::Boot.allow_job('RedmineAwsSqsTestJob')
          with_sqs_client(stub_client(dead_letter: dead_letter)) do
            ::Aws::ActiveJob::SQS::LambdaHandler.job_handler(event: lambda_event(body, receives: receives),
                                                             context: nil)
          end
        end
      end

      def body(fail:)
        job_body(RedmineAwsSqsTestJob.new(fail))
      end

      def test_a_job_runs
        assert_no_difference('AwsSqsJobFailure.count') { handle(body(fail: false), receives: 1) }
        assert_equal 1, RedmineAwsSqsTestJob.runs
      end

      def test_a_failure_before_the_last_receive_is_retried_and_not_recorded
        assert_no_difference('AwsSqsJobFailure.count') do
          assert_raises(ArgumentError) { handle(body(fail: true), receives: 2) }
        end
      end

      def test_a_failure_on_the_last_receive_is_recorded_and_raised
        assert_difference('AwsSqsJobFailure.count', 1) do
          assert_raises(ArgumentError) { handle(body(fail: true), receives: 3) }
        end
        failure = AwsSqsJobFailure.last

        assert_equal 'RedmineAwsSqsTestJob', failure.job_class
        assert_equal 'ArgumentError', failure.error_class
        assert_equal 3, failure.attempts
        assert_not_nil failure.enqueued_at
      end

      def test_nothing_is_recorded_without_a_dead_letter_queue
        assert_no_difference('AwsSqsJobFailure.count') do
          assert_raises(ArgumentError) { handle(body(fail: true), receives: 10, dead_letter: false) }
        end
      end

      def test_a_job_class_outside_the_allowlist_does_not_run_and_is_dropped
        body = { job_class: 'RedmineAwsSqsNotAllowedJob', job_id: '1', arguments: [] }.to_json

        assert_difference('AwsSqsJobFailure.count', 1) do
          assert_match(/Dropped 1 job/, handle(body, receives: 1))
        end
        assert_equal 'Aws::ActiveJob::SQS::InvalidJobClassError', AwsSqsJobFailure.last.error_class
      end

      # The gem deletes the message at the URL of its private to_queue_url,
      # which the patch replaces for the job queue. This fails if the gem
      # stops building the URL there.
      def test_the_message_is_deleted_at_the_configured_queue_url
        url = 'http://localstack:4566/000000000000/redmine-jobs'
        client = stub_client
        with_queue_url(url) do
          RedmineAws::SQS::Boot.allow_job('RedmineAwsSqsTestJob')
          with_sqs_client(client) do
            ::Aws::ActiveJob::SQS::LambdaHandler.job_handler(event: lambda_event(body(fail: false)), context: nil)
          end
        end
        deletions = client.api_requests.select { |r| r[:operation_name] == :delete_message }

        assert_equal([url], deletions.map { |r| r[:params][:queue_url] })
      end

      def test_another_queue_keeps_the_url_from_its_arn
        other = 'arn:aws:sqs:us-east-1:123456789012:other-queue'
        record = lambda_event('{}', arn: other)['Records'][0]
        with_queue_url(QUEUE_URL) do
          assert_nil LambdaHandlerPatch.configured_queue_url(other)
          assert_equal 'https://sqs.us-east-1.amazonaws.com/123456789012/other-queue',
                       ::Aws::ActiveJob::SQS::LambdaHandler.send(:to_queue_url, record)
        end
      end

      # The gem writes the whole event to the function's log; the patch writes
      # the line without it.
      def test_the_event_is_not_written_to_the_log
        body = job_body(Mailer.delivery_job.new('Mailer', 'account_information', 'deliver_now',
                                                args: [User.find(2), 'pw-secret-10']))
        out, = capture_io { handle(body, receives: 1) }

        assert_includes out, "job_handler running\n"
        assert_not_includes out, 'pw-secret-10'
        assert_includes out, 'Running job: '
      end

      # The failure's log line has the job with its arguments filtered, the
      # error's class and message; the page shows the class only.
      def test_a_recorded_failure_is_logged
        io = StringIO.new
        saved = Rails.logger
        Rails.logger = Logger.new(io)
        assert_raises(ArgumentError) { handle(body(fail: true), receives: 3) }

        line = io.string[/\[redmine_aws_sqs\] job failed.*/]

        assert_match(/\Ajob failed after 3 receive\(s\): RedmineAwsSqsTestJob \(Job ID: [-0-9a-f]+\) /,
                     line.delete_prefix('[redmine_aws_sqs] '))
        assert line.end_with?('perform(fail: true): ArgumentError: the job failed'), line
      ensure
        Rails.logger = saved
      end

      # A body that is not JSON: the parser error's message quotes it, so the
      # result and the log name the class only.
      def test_a_body_that_is_not_json_is_not_quoted
        io = StringIO.new
        saved = Rails.logger
        Rails.logger = Logger.new(io)
        result = handle('{"password": "pw-secret-11"', receives: 1)

        assert_equal 'Dropped 1 job(s): JSON::ParserError', result
        assert_includes io.string, 'unknown (Job ID: ) perform(): JSON::ParserError'
        assert_not_includes io.string, 'pw-secret-11'
      ensure
        Rails.logger = saved
      end

      def test_a_class_that_is_not_a_job_does_not_run
        body = { job_class: 'Kernel', job_id: '1', arguments: [] }.to_json

        assert_match(/Dropped/, handle(body, receives: 1))
      end
    end
  end
end
