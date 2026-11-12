# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # Every record that fails to resend is named in the flash, not only the
    # last one.
    class AwsSqsJobsResendErrorsTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def test_each_failed_record_is_named
        @request.session[:user_id] = 1
        resend_refused(%w[test_email lost_password].map { |mail| record_failure(mail_job(mail, User.find(1))) })

        %w[test_email lost_password].each do |mail|
          assert_includes flash[:error], "Mailer##{mail}: Could not call the SQS API (Aws::SQS::Errors::AccessDenied)."
        end
      end

      private

      # Resends the records with SQS refusing every message.
      def resend_refused(records)
        client = stub_client
        client.stub_responses(:send_message, 'AccessDenied')
        with_queue_url(QUEUE_URL) { with_sqs_client(client) { post :resend, params: { ids: records.map(&:id) } } }
      end
    end
  end
end
