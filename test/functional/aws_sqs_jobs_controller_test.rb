# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAwsSqs
  class AwsSqsJobsControllerTest < Redmine::ControllerTest
    include RedmineAwsSqs::TestHelper

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
      assert_select 'h3', text: 'Queue'
      assert_select 'div.box.tabular p label', text: 'Messages available'
      assert_select 'div.box.tabular p', text: /Messages available\s*3/
      assert_select 'div.box.tabular p', text: /Dead-letter queue\s*2/
      assert_select 'p a.icon.icon-reload[data-method=post]', text: 'Start DLQ redrive'
    end

    def test_index_opens_when_sqs_fails
      client = stub_aws_client(Aws::SQS::Client, get_queue_attributes: 'AccessDenied')
      with_queue_url(QUEUE_URL) do
        with_sqs_client(client) { get :index }
      end

      assert_response :success
      assert_select 'div.flash.error', text: 'Could not call the SQS API (AccessDenied). See the log for details.'
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

    def test_non_administrators_are_refused
      @request.session[:user_id] = 2
      get :index

      assert_response :forbidden
      post :redrive

      assert_response :forbidden
    end
  end
end
