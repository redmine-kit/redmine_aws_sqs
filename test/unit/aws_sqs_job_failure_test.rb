# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    class AwsSqsJobFailureTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def mail_failure
        body = job_body(mail_job('test_email', User.find(1)))
        AwsSqsJobFailure.record!(body, Net::SMTPFatalError.new('rejected'), attempts: 3)
      end

      def test_a_mail_job_is_summarized_as_the_mail
        failure = mail_failure

        assert_equal Mailer.delivery_job.name, failure.job_class
        assert_equal 'Mailer#test_email', failure.summary
        assert_predicate failure, :mail?
      end

      def test_the_error_class_and_the_attempts_are_kept
        failure = mail_failure

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

        assert_not AwsSqsJobFailure.exists?(failure.id)
        assert(client.api_requests.any? { |r| r[:operation_name] == :send_message })
      end

      # Mailer#account_information's password is not in the table.
      def test_a_job_with_a_secret_is_kept_encrypted
        body = job_body(mail_job('account_information', User.find(2), 'secret-password-42'))
        failure = AwsSqsJobFailure.record!(body, RuntimeError.new('x'), attempts: 3)

        assert_not_includes AwsSqsJobFailure.where(id: failure.id).pick(:job_data), 'secret-password-42'
        assert_equal body, failure.reload.job_body
      end

      def test_a_job_with_a_secret_is_resent_as_it_was
        body = job_body(mail_job('account_information', User.find(2), 'secret-password-42'))
        client = stub_client
        AwsSqsJobFailure.record!(body, RuntimeError.new('x'), attempts: 3)
                        .resend!(RedmineAws::SQS::Queue.new(url: QUEUE_URL, client: client))
        sent = client.api_requests.find { |r| r[:operation_name] == :send_message }

        assert_equal body, sent[:params][:message_body]
      end

      def test_a_job_without_a_secret_is_kept_as_it_is
        body = job_body(mail_job('test_email', User.find(1)))

        assert_equal body, AwsSqsJobFailure.record!(body, RuntimeError.new('x'), attempts: 3).job_data
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
