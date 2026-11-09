# frozen_string_literal: true

require_relative '../test_helper'

class RedmineServerlessSqsTestJob < ActiveJob::Base
  cattr_accessor :runs, default: 0

  def perform(fail)
    self.class.runs += 1
    raise ArgumentError, 'the job failed' if fail
  end
end

module RedmineServerlessSqs
  # aws-activejob-sqs's handler with the plugin's patch, on SDK response stubs.
  class LambdaHandlerPatchTest < ActiveSupport::TestCase
    include RedmineServerlessSqs::TestHelper

    def setup
      RedmineServerlessSqsTestJob.runs = 0
    end

    def handle(body, receives:, dead_letter: true)
      with_queue_url(QUEUE_URL) do
        RedmineServerlessSqsBoot.allow_job('RedmineServerlessSqsTestJob')
        with_sqs_client(stub_client(dead_letter: dead_letter)) do
          Aws::ActiveJob::SQS::LambdaHandler.job_handler(event: lambda_event(body, receives: receives), context: nil)
        end
      end
    end

    def body(fail:)
      job_body(RedmineServerlessSqsTestJob.new(fail))
    end

    def test_a_job_runs
      assert_no_difference('ServerlessJobFailure.count') { handle(body(fail: false), receives: 1) }
      assert_equal 1, RedmineServerlessSqsTestJob.runs
    end

    def test_a_failure_before_the_last_receive_is_retried_and_not_recorded
      assert_no_difference('ServerlessJobFailure.count') do
        assert_raises(ArgumentError) { handle(body(fail: true), receives: 2) }
      end
    end

    def test_a_failure_on_the_last_receive_is_recorded_and_raised
      assert_difference('ServerlessJobFailure.count', 1) do
        assert_raises(ArgumentError) { handle(body(fail: true), receives: 3) }
      end
      failure = ServerlessJobFailure.last

      assert_equal 'RedmineServerlessSqsTestJob', failure.job_class
      assert_equal 'ArgumentError', failure.error_class
      assert_equal 'the job failed', failure.error_message
      assert_equal 3, failure.attempts
      assert_not_nil failure.enqueued_at
    end

    def test_nothing_is_recorded_without_a_dead_letter_queue
      assert_no_difference('ServerlessJobFailure.count') do
        assert_raises(ArgumentError) { handle(body(fail: true), receives: 10, dead_letter: false) }
      end
    end

    def test_a_job_class_outside_the_allowlist_does_not_run_and_is_dropped
      body = { job_class: 'RedmineServerlessSqsNotAllowedJob', job_id: '1', arguments: [] }.to_json

      assert_difference('ServerlessJobFailure.count', 1) do
        assert_match(/Dropped 1 job/, handle(body, receives: 1))
      end
      assert_equal 'Aws::ActiveJob::SQS::InvalidJobClassError', ServerlessJobFailure.last.error_class
    end

    def test_the_message_is_deleted_at_the_configured_queue_url
      with_queue_url('http://localstack:4566/000000000000/redmine-jobs') do
        assert_equal 'http://localstack:4566/000000000000/redmine-jobs',
                     LambdaHandlerPatch.configured_queue_url(QUEUE_ARN)
      end
    end

    def test_another_queue_keeps_the_url_from_its_arn
      other = 'arn:aws:sqs:us-east-1:123456789012:other-queue'
      record = lambda_event('{}', arn: other)['Records'][0]
      with_queue_url(QUEUE_URL) do
        assert_nil LambdaHandlerPatch.configured_queue_url(other)
        assert_equal 'https://sqs.us-east-1.amazonaws.com/123456789012/other-queue',
                     Aws::ActiveJob::SQS::LambdaHandler.send(:to_queue_url, record)
      end
    end

    def test_a_class_that_is_not_a_job_does_not_run
      body = { job_class: 'Kernel', job_id: '1', arguments: [] }.to_json

      assert_match(/Dropped/, handle(body, receives: 1))
    end
  end
end
