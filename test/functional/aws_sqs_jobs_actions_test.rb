# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # The actions of the "Jobs" tab: resending, deleting and the DLQ redrive.
    class AwsSqsJobsActionsTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def setup
        @request.session[:user_id] = 1
      end

      # Resends the record with SQS refusing the message; the log of the request.
      def failing_resend(record)
        client = stub_client
        client.stub_responses(:send_message, 'AccessDenied')
        capture_log(ActionController::Base) do
          with_queue_url(QUEUE_URL) do
            with_sqs_client(client) { post :resend, params: { ids: [record.id] } }
          end
        end
      end

      def test_resend
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        client = stub_client
        with_queue_url(QUEUE_URL) do
          with_sqs_client(client) { post :resend, params: { ids: [record.id] } }
        end

        assert_redirected_to '/admin/aws/jobs'
        assert_not AwsSqsJobFailure.exists?(record.id)
        assert(client.api_requests.any? { |r| r[:operation_name] == :send_message })
      end

      def test_a_failed_resend_keeps_the_record
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        failing_resend(record)

        assert AwsSqsJobFailure.exists?(record.id)
        assert_match(/AccessDenied/, flash[:error])
      end

      # A failed resend: the page names the error's class; the log has the
      # job's class, ID and summary (never the body) and the error's message.
      def test_a_failed_resend_is_logged_with_the_job
        log = failing_resend(record_failure(mail_job('account_information', User.find(2), 'pw-23')))

        assert_equal 'Mailer#account_information: Could not call the SQS API (Aws::SQS::Errors::AccessDenied). ' \
                     'See the log for details.', flash[:error]
        assert_match(/Mailer::DeliveryJob \(Job ID: \S+\) Mailer#account_information: Aws::SQS::Errors::AccessDenied/,
                     log)
        assert_not_includes log, 'pw-23'
      end

      def test_destroy
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        post :destroy, params: { ids: [record.id] }

        assert_redirected_to '/admin/aws/jobs'
        assert_not AwsSqsJobFailure.exists?(record.id)
      end

      def test_redrive
        client = stub_client
        client.stub_responses(:start_message_move_task, task_handle: 'task-1')
        with_queue_url(QUEUE_URL) do
          with_sqs_client(client) { post :redrive }
        end

        assert_redirected_to '/admin/aws/jobs'
        assert(client.api_requests.any? { |r| r[:operation_name] == :start_message_move_task })
      end

      def test_operations_are_logged
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        log = capture_log(ActionController::Base) { post :destroy, params: { ids: [record.id] } }

        assert_match(/\[redmine_aws_sqs\] admin deleted 1 failure record/, log)
      end
    end
  end
end
