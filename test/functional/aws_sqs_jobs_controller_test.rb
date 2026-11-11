# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    class AwsSqsJobsControllerTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def setup
        @request.session[:user_id] = 1
      end

      def record_failure(job, error: RuntimeError.new('boom'))
        AwsSqsJobFailure.record!(job_body(job), error, attempts: 3, enqueued_at: 1.hour.ago)
      end

      def mail_job
        Mailer.delivery_job.new('Mailer', 'test_email', 'deliver_now', args: [User.find(1)])
      end

      def test_index_shows_the_counts
        with_queue_url(QUEUE_URL) do
          with_sqs_client(stub_client) { get :index }
        end

        assert_response :success
        # The tab of the "AWS" page of redmine_aws, with its menu item selected.
        assert_select 'h2', text: 'AWS'
        assert_select '.tabs a.selected', text: 'Jobs'
        assert_select '#admin-menu a.selected', text: /AWS/
        assert_select 'h3', text: 'Queue'
        assert_select 'table.list.values td.name', text: 'Messages available'
        assert_select 'table.list.values tr', text: /Messages available\s*3/
        assert_select 'table.list.values tr', text: /Dead-letter queue\s*2/
        assert_select 'p a.icon.icon-reload[data-method=post]', text: 'Start DLQ redrive'
      end

      def test_index_opens_when_sqs_fails
        client = stub_aws_client(::Aws::SQS::Client, get_queue_attributes: 'AccessDenied')
        with_queue_url(QUEUE_URL) do
          with_sqs_client(client) { get :index }
        end

        assert_response :success
        assert_select 'div.flash.error',
                      text: 'Could not call the SQS API (Aws::SQS::Errors::AccessDenied). See the log for details.'
        assert_not_includes response.body, 'stubbed response error', 'the raw exception message stays in the log'
      end

      def test_index_without_the_queue_url
        with_queue_url(nil) { get :index }

        assert_response :success
        assert_select 'p.warning', text: /REDMINE_JOBS_QUEUE_URL/
      end

      def test_index_lists_failures_and_filters_mail
        record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        record_failure(mail_job)
        with_queue_url(nil) { get :index }

        assert_select '#aws-sqs-job-failures tbody tr', 2
        # The check box in the header row toggles the rows, as in Redmine's issue list.
        assert_select '#aws-sqs-job-failures th.checkbox input.toggle-selection[type=checkbox]'
        assert_select 'script[src*="context_menu"]'
        assert_select 'a', text: 'Check all', count: 0
        with_queue_url(nil) { get :index, params: { mail: '1' } }

        assert_select '#aws-sqs-job-failures tbody tr', 1
        assert_select '#aws-sqs-job-failures tbody tr', text: /Mailer#test_email/
      end

      # The error's class only, as Redmine AWS's connection checks show it; the
      # message is in the log.
      def test_the_list_shows_the_error_class_only
        record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'), error: ArgumentError.new('message-secret-22'))
        with_queue_url(nil) { get :index }

        assert_select '#aws-sqs-job-failures tbody td.description', text: 'ArgumentError'
        assert_not_includes response.body, 'message-secret-22'
      end

      # A failed resend: the page names the error's class; the log has the
      # job with its arguments filtered and the error's message.
      def test_a_failed_resend_is_logged_with_the_job
        job = Mailer.delivery_job.new('Mailer', 'account_information', 'deliver_now', args: [User.find(2), 'pw-23'])
        record = record_failure(job)
        client = stub_client
        client.stub_responses(:send_message, 'AccessDenied')
        io = StringIO.new
        saved = ActionController::Base.logger
        ActionController::Base.logger = Logger.new(io)
        with_queue_url(QUEUE_URL) do
          with_sqs_client(client) { post :resend, params: { ids: [record.id] } }
        end

        assert_equal 'Mailer#account_information: Could not call the SQS API (Aws::SQS::Errors::AccessDenied). ' \
                     'See the log for details.', flash[:error]
        assert_includes io.string, "Mailer#account_information(user: #{User.find(2).to_global_id}, " \
                                   'password: [FILTERED]): Aws::SQS::Errors::AccessDenied: ' \
                                   'stubbed-response-error-message'
        assert_not_includes io.string, 'pw-23'
      ensure
        ActionController::Base.logger = saved
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
        client = stub_client
        client.stub_responses(:send_message, 'AccessDenied')
        with_queue_url(QUEUE_URL) do
          with_sqs_client(client) { post :resend, params: { ids: [record.id] } }
        end

        assert AwsSqsJobFailure.exists?(record.id)
        assert_match(/AccessDenied/, flash[:error])
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
        io = StringIO.new
        saved = ActionController::Base.logger
        ActionController::Base.logger = Logger.new(io)
        post :destroy, params: { ids: [record.id] }

        assert_match(/\[redmine_aws_sqs\] admin deleted 1 failure record/, io.string)
      ensure
        ActionController::Base.logger = saved
      end

      def test_no_message_bodies_on_the_page
        record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        with_queue_url(nil) { get :index }

        assert_not_includes response.body, '_aj_globalid'
        assert_not_includes response.body, 'job_class'
      end

      ACTIONS = [%i[get index], %i[post resend], %i[post destroy], %i[post redrive]].freeze

      def test_only_administrators
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        client = stub_client
        client.stub_responses(:start_message_move_task, task_handle: 'task-1')
        { 2 => :forbidden, nil => :redirect }.each do |user_id, status|
          ACTIONS.each do |method, action|
            @request.session[:user_id] = user_id
            with_queue_url(QUEUE_URL) do
              with_sqs_client(client) { process action, method: method.to_s.upcase, params: { ids: [record.id] } }
            end

            assert_response status, "#{method} #{action} as user #{user_id.inspect}"
          end
        end
        assert AwsSqsJobFailure.exists?(record.id)
        assert_empty client.api_requests
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
