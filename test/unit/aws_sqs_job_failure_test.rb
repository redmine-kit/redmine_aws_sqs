# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    class AwsSqsJobFailureTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def test_a_mail_job_is_summarized_as_the_mail
        body = job_body(Mailer.delivery_job.new('Mailer', 'test_email', 'deliver_now', args: [User.find(1)]))
        failure = AwsSqsJobFailure.record!(body, Net::SMTPFatalError.new('rejected'), attempts: 3)

        assert_equal Mailer.delivery_job.name, failure.job_class
        assert_equal 'Mailer#test_email', failure.summary
        assert_predicate failure, :mail?
        assert_equal 'Net::SMTPFatalError', failure.error_class
        assert_equal 3, failure.attempts
      end

      def test_a_body_that_is_not_a_job_is_kept
        failure = AwsSqsJobFailure.record!('not json', RuntimeError.new('x'), attempts: 1)

        assert_equal 'unknown', failure.job_class
        assert_equal 'not json', failure.job_data
      end

      # The page shows the error's class only; the message is in the log
      # (Failures.log), and the record does not keep it.
      def test_the_error_message_is_not_kept
        failure = AwsSqsJobFailure.record!('{}', RuntimeError.new('message-secret-21'), attempts: 1)

        assert_equal 'RuntimeError', failure.error_class
        assert_not_includes AwsSqsJobFailure.column_names, 'error_message'
        assert_not_includes failure.attributes.values.map(&:to_s), 'message-secret-21'
      end

      def test_resend_puts_the_job_back_and_removes_the_record
        body = job_body(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        failure = AwsSqsJobFailure.record!(body, RuntimeError.new('x'), attempts: 3)
        client = stub_client
        failure.resend!(RedmineAws::SQS::Queue.new(url: QUEUE_URL, client: client))

        assert failure.destroyed?
        assert(client.api_requests.any? { |r| r[:operation_name] == :send_message })
      end

      def test_prune
        old = AwsSqsJobFailure.record!('{}', RuntimeError.new('x'), attempts: 1)
        old.update_column(:failed_at, 91.days.ago)
        AwsSqsJobFailure.record!('{}', RuntimeError.new('x'), attempts: 1)

        assert_equal 1, AwsSqsJobFailure.prune
        assert_equal 0, AwsSqsJobFailure.prune(30)
        assert_equal 1, AwsSqsJobFailure.count
      end
    end
  end
end
