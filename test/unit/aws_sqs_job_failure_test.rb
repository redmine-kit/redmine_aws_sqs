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

      def test_long_errors_are_cut
        failure = AwsSqsJobFailure.record!('{}', RuntimeError.new('x' * 10_000), attempts: 1)

        assert_equal AwsSqsJobFailure::MAX_ERROR, failure.error_message.size
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
