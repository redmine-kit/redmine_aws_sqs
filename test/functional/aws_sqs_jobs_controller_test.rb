# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # The "Jobs" tab: the queue counts and the list of failed jobs.
    class AwsSqsJobsControllerTest < Redmine::ControllerTest
      include RedmineAws::SQS::TestHelper

      tests AwsSqsJobsController

      def setup
        @request.session[:user_id] = 1
      end

      def index_with_counts
        with_queue_url(QUEUE_URL) do
          with_sqs_client(stub_client) { get :index }
        end
      end

      # The tab of the "AWS" page of redmine_aws, with its menu item selected.
      def test_index_is_a_tab_of_the_aws_page
        index_with_counts

        assert_response :success
        assert_select 'h2', text: 'AWS'
        assert_select '.tabs a.selected', text: 'Jobs'
        assert_select '#admin-menu a.selected', text: /AWS/
      end

      def test_index_shows_the_counts
        index_with_counts

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
        record_failure(mail_job('test_email', User.find(1)))
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

      def test_no_message_bodies_on_the_page
        record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        with_queue_url(nil) { get :index }

        assert_not_includes response.body, '_aj_globalid'
        assert_not_includes response.body, 'job_class'
      end
    end
  end
end
