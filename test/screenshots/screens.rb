# frozen_string_literal: true

require_relative '../test_helper'
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/screenshot_case')

module RedmineAws
  module SQS
    # The screens of docs/admin.md: the Jobs tab with a queue that has a
    # dead-letter queue (SDK response stubs; the account and the names are
    # examples) and records of jobs that failed.
    class ScreenshotsTest < RedmineAws::ScreenshotCase
      self.docs = File.expand_path('../../docs', __dir__)

      QUEUE_URL = 'https://sqs.ap-northeast-1.amazonaws.com/111122223333/redmine-jobs'
      QUEUE_ARN = 'arn:aws:sqs:ap-northeast-1:111122223333:redmine-jobs'
      DLQ_URL = 'https://sqs.ap-northeast-1.amazonaws.com/111122223333/redmine-jobs-dlq'
      DLQ_ARN = 'arn:aws:sqs:ap-northeast-1:111122223333:redmine-jobs-dlq'
      QUEUE_ATTRIBUTES = {
        'QueueArn' => QUEUE_ARN, 'ApproximateNumberOfMessages' => '3', 'ApproximateNumberOfMessagesNotVisible' => '1',
        'ApproximateNumberOfMessagesDelayed' => '0',
        'RedrivePolicy' => { deadLetterTargetArn: DLQ_ARN, maxReceiveCount: 3 }.to_json
      }.freeze
      DEAD_LETTER_ATTRIBUTES = { 'ApproximateNumberOfMessages' => '2' }.freeze
      # Job class, summary, queue, error class, attempts, how long ago.
      FAILURES = [
        ['Mailer::DeliveryJob', 'Mailer#issue_edit', 'mailers', 'Net::ReadTimeout', 3, 3.hours],
        ['DestroyProjectJob', 'DestroyProjectJob', 'default', 'ActiveRecord::StatementInvalid', 3, 26.hours]
      ].freeze

      def setup
        super
        @saved_url = ENV.fetch('REDMINE_JOBS_QUEUE_URL', nil)
        ENV['REDMINE_JOBS_QUEUE_URL'] = QUEUE_URL
        @config = ::Aws::ActiveJob::SQS.config
        @saved_client = @config.client
        @config.client = stub_client
        record_failures
      end

      def teardown
        @config.client = @saved_client
        @saved_url ? ENV['REDMINE_JOBS_QUEUE_URL'] = @saved_url : ENV.delete('REDMINE_JOBS_QUEUE_URL')
      end

      def test_screens
        each_language do |language|
          visit '/admin/aws/jobs'
          assert_selector '#aws-sqs-job-failures'
          shoot 'jobs', language
        end
      end

      private

      def stub_client
        client = ::Aws::SQS::Client.new(stub_responses: true, region: 'ap-northeast-1')
        client.stub_responses(:get_queue_attributes, lambda { |context|
          { attributes: context.params[:queue_url] == DLQ_URL ? DEAD_LETTER_ATTRIBUTES : QUEUE_ATTRIBUTES }
        })
        client.stub_responses(:get_queue_url, queue_url: DLQ_URL)
        client
      end

      def record_failures
        now = Time.current
        FAILURES.each_with_index do |(job_class, summary, queue, error, attempts, ago), index|
          AwsSqsJobFailure.create!(
            job_class: job_class, job_id: SecureRandom.uuid, queue_name: queue, summary: summary,
            job_data: { job_class: job_class, arguments: [] }.to_json, error_class: error, attempts: attempts,
            enqueued_at: now - ago - 10.minutes, failed_at: now - ago + index.minutes
          )
        end
      end
    end
  end
end
