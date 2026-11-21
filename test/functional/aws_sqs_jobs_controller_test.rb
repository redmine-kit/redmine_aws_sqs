# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Sqs
      # The "Jobs" tab: the queue counts as the last refresh stored them, and
      # the list of failed jobs.
      class AwsSqsJobsControllerTest < Redmine::ControllerTest
        include RedmineKit::Aws::Sqs::TestHelper

        tests AwsSqsJobsController

        def setup
          @request.session[:user_id] = 1
        end

        # The page after a refresh stored the counts read with client; the
        # page itself calls nothing.
        def index_with_counts(client = stub_client)
          page_client = stub_client
          with_queue_url(QUEUE_URL) do
            with_sqs_client(client) { AwsSqsSnapshot.refresh! }
            with_sqs_client(page_client) { get :index }
          end
          assert_empty page_client.api_requests, 'the page calls SQS'
        end

        # The tab of the "AWS" page of redmine_kit_aws, with its menu item selected.
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
          assert_select '#aws-sqs-jobs-updated', text: /\AUpdated: .+ \|\s*Refresh\z/
          assert_select '#aws-sqs-jobs-updated a.icon-reload[data-method=post][href=?]', '/admin/aws/jobs/refresh'
        end

        # Before the first refresh: no counts, the Refresh link, no SQS call.
        def test_index_before_the_first_refresh
          client = stub_client
          with_queue_url(QUEUE_URL) do
            with_sqs_client(client) { get :index }
          end

          assert_response :success
          assert_select 'h3 + p.nodata', text: 'No data to display'
          assert_select '#aws-sqs-jobs-updated', text: 'Refresh'
          assert_select 'table.list.values', 0
          assert_empty client.api_requests
        end

        # Counts read for another queue (REDMINE_SQS_QUEUE_URL changed since)
        # are not shown.
        def test_index_does_not_show_the_counts_of_another_queue
          with_queue_url('https://sqs.us-east-1.amazonaws.com/123456789012/other') do
            with_sqs_client(stub_client) { AwsSqsSnapshot.refresh! }
          end
          with_queue_url(QUEUE_URL) { get :index }

          assert_select 'p.nodata', text: 'No data to display'
          assert_select 'table.list.values', 0
        end

        def test_index_opens_when_sqs_fails
          index_with_counts(stub_aws_client(::Aws::SQS::Client, get_queue_attributes: 'AccessDenied'))

          assert_response :success
          assert_select 'div.flash.error',
                        text: 'Could not call the SQS API (Aws::SQS::Errors::AccessDenied). See the log for details.'
          assert_not_includes response.body, 'stubbed response error', 'the raw exception message stays in the log'
        end

        def test_index_without_the_queue_url
          with_queue_url(nil) { get :index }

          assert_response :success
          assert_select 'p.warning', text: /REDMINE_SQS_QUEUE_URL/
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

        # The error's class only, as Redmine Kit AWS's connection checks show it; the
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
end
