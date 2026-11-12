# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # A record whose body was encrypted under another secret_key_base: its
    # resend fails by itself, shown by the error's class, and the other
    # selected records are still sent.
    class AwsSqsJobsUndecryptableTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def test_the_record_is_kept_and_named_by_the_error_class
        stale = undecryptable_record
        resend(stale, record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1')))

        assert_redirected_to '/admin/aws/jobs'
        assert_match(/ActiveSupport::MessageEncryptor::InvalidMessage/, flash[:error])
        assert AwsSqsJobFailure.exists?(stale.id)
      end

      def test_the_other_records_are_still_resent
        good = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        client = resend(undecryptable_record, good)

        assert_not AwsSqsJobFailure.exists?(good.id)
        assert_equal(1, client.api_requests.count { |r| r[:operation_name] == :send_message })
      end

      private

      def resend(*records)
        @request.session[:user_id] = 1
        client = stub_client
        with_queue_url(QUEUE_URL) { with_sqs_client(client) { post :resend, params: { ids: records.map(&:id) } } }
        client
      end

      def undecryptable_record
        body = job_body(mail_job('account_information', User.find(2), 'pw-31'))
        record = AwsSqsJobFailure.record!(body, RuntimeError.new('x'), attempts: 3)
        other = AwsSqsJobFailure.encryptor('another secret_key_base').encrypt_and_sign(body)
        record.update_column(:job_data, AwsSqsJobFailure::ENCRYPTED + other)
        record
      end
    end
  end
end
