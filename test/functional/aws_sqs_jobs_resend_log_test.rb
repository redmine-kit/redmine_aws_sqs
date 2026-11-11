# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # A record whose body is not JSON fails to resend; the log names the
    # error's class only, as a parser's message quotes the untrusted body.
    class AwsSqsJobsResendLogTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def test_the_body_of_a_failed_resend_is_not_logged
        @request.session[:user_id] = 1
        record = AwsSqsJobFailure.record!('not json body-secret-77', RuntimeError.new('x'), attempts: 1)
        log = capture_log(ActionController::Base) do
          with_queue_url(QUEUE_URL) do
            with_sqs_client(stub_client) { post :resend, params: { ids: [record.id] } }
          end
        end

        assert_match(/JSON::ParserError$/, log)
        assert_not_includes log, 'body-secret-77'
        assert AwsSqsJobFailure.exists?(record.id)
      end
    end
  end
end
