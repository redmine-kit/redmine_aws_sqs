# frozen_string_literal: true

require_relative '../test_helper'
require 'rake'

module RedmineKit
  module Aws
    module Sqs
      # The queue counts that the Jobs tab shows (AwsSqsSnapshot), and the rake
      # task redmine_kit:aws:sqs:refresh that reads them.
      class RefreshTest < ActiveSupport::TestCase
        include RedmineKit::Aws::Sqs::TestHelper

        setup do
          Rails.application.load_tasks unless Rake::Task.task_defined?('redmine_kit:aws:sqs:refresh')
        end

        def refresh(client = stub_client)
          with_queue_url(QUEUE_URL) { with_sqs_client(client) { AwsSqsSnapshot.refresh! } }
        end

        # The output, or the SystemExit of abort.
        def rake_refresh(client = stub_client, url: QUEUE_URL)
          task = Rake::Task['redmine_kit:aws:sqs:refresh']
          task.reenable
          with_queue_url(url) { with_sqs_client(client) { capture_io { task.invoke } } }
        end

        def test_refresh_stores_the_counts_and_keeps_the_latest_only
          refresh(stub_client(waiting: 5))
          snapshot = refresh(stub_client(waiting: 7))

          assert_equal 1, AwsSqsSnapshot.count
          assert_equal({ waiting: 7, running: 1, delayed: 0, dead_letter: 2 }, snapshot.reload.counts(QUEUE_URL))
          assert_nil snapshot.error(QUEUE_URL)
        end

        # The counts of another queue (REDMINE_SQS_QUEUE_URL changed since) are
        # not shown as this queue's.
        def test_the_counts_are_the_queue_s_they_were_read_for
          snapshot = refresh

          assert_nil snapshot.counts('https://sqs.us-east-1.amazonaws.com/123456789012/other')
        end

        # The error's class is stored; its message, which may name accounts
        # or resources, goes to the log only.
        def test_an_error_is_stored_by_its_class
          client = stub_aws_client(::Aws::SQS::Client, get_queue_attributes: 'AccessDenied')
          snapshot = nil
          log = capture_log(ActiveRecord::Base) { snapshot = refresh(client) }

          assert_nil snapshot.counts(QUEUE_URL)
          assert_equal 'Aws::SQS::Errors::AccessDenied', snapshot.error(QUEUE_URL)
          assert_not_includes snapshot.data.to_json, 'stubbed response error'
          assert_includes log, 'could not read the queue counts: Aws::SQS::Errors::AccessDenied'
        end

        def test_the_task_is_in_the_redmine_kit_namespace
          assert Rake::Task.task_defined?('redmine_kit:aws:sqs:refresh')
          assert_empty Rake::Task['redmine_kit:aws:sqs:refresh'].arg_names
        end

        def test_the_task_stores_the_counts
          out, = rake_refresh

          assert_equal "refreshed the queue counts\n", out
          assert_equal 3, AwsSqsSnapshot.latest.counts(QUEUE_URL)[:waiting]
        end

        # A failure aborts the task, so that a schedule shows it.
        def test_the_task_fails_when_sqs_fails
          client = stub_aws_client(::Aws::SQS::Client, get_queue_attributes: 'AccessDenied')
          error = assert_raises(SystemExit) { rake_refresh(client) }

          assert_not error.success?
          assert_equal 'Aws::SQS::Errors::AccessDenied', AwsSqsSnapshot.latest.error(QUEUE_URL)
        end

        def test_the_task_without_the_queue_url_reads_nothing
          client = stub_client
          error = assert_raises(SystemExit) { rake_refresh(client, url: nil) }

          assert_not error.success?
          assert_empty client.api_requests
          assert_equal 0, AwsSqsSnapshot.count
        end
      end
    end
  end
end
