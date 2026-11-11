# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # Who may use the "Jobs" tab, how, and with which parameters.
    class AwsSqsJobsSecurityTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def setup
        @request.session[:user_id] = 1
      end

      ACTIONS = [%i[get index], %i[post resend], %i[post destroy], %i[post redrive]].freeze

      def request_as(user_id, method, action, ids)
        @request.session[:user_id] = user_id
        with_queue_url(QUEUE_URL) do
          with_sqs_client(@client) { process action, method: method.to_s.upcase, params: { ids: ids } }
        end
      end

      def test_only_administrators
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        @client = stub_client
        { 2 => :forbidden, nil => :redirect }.each do |user_id, status|
          ACTIONS.each do |method, action|
            request_as(user_id, method, action, [record.id])

            assert_response status, "#{method} #{action} as user #{user_id.inspect}"
          end
        end
        assert AwsSqsJobFailure.exists?(record.id)
        assert_empty @client.api_requests
      end

      def test_state_changes_only_by_post
        %w[resend destroy redrive].each do |action|
          assert_raises(ActionController::RoutingError, action) do
            Rails.application.routes.recognize_path("/admin/aws/jobs/#{action}", method: :get)
          end
        end
      end

      # ids[] of the list's check boxes, and what else a request could send.
      def test_unexpected_ids
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        [{}, { ids: [] }, { ids: '' }, { ids: record.id.to_s }, { ids: { a: record.id.to_s } },
         { ids: ['abc'] }, { ids: [[record.id.to_s]] }, { ids: ['99999999999999999999'] }].each do |params|
          post :destroy, params: params

          assert_response :not_found, params.inspect
        end
        assert AwsSqsJobFailure.exists?(record.id)
      end

      # The job's summary comes from the message body; Redmine shows flash
      # messages as HTML.
      def test_a_failed_resend_escapes_the_summary
        body = { job_class: '<img src=x onerror=alert(1)>', job_id: '1', arguments: [] }.to_json
        record = AwsSqsJobFailure.record!(body, RuntimeError.new('boom'), attempts: 1)
        with_queue_url(QUEUE_URL) do
          with_sqs_client(stub_client) { post :resend, params: { ids: [record.id] } }
        end

        assert_equal '&lt;img src=x onerror=alert(1)&gt;: Could not call the SQS API (ArgumentError). ' \
                     'See the log for details.', flash[:error]
        assert AwsSqsJobFailure.exists?(record.id)
      end
    end
  end
end
