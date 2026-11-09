# frozen_string_literal: true

require_relative 'screenshot_case'

# The screens of docs/admin.md: the Jobs tab with a queue that has a
# dead-letter queue (SDK response stubs; the account and the names are
# examples) and records of jobs that failed.
class RedmineServerlessSqsScreens < ScreenshotCase
  QUEUE_URL = 'https://sqs.ap-northeast-1.amazonaws.com/111122223333/redmine-jobs'
  QUEUE_ARN = 'arn:aws:sqs:ap-northeast-1:111122223333:redmine-jobs'
  DLQ_URL = 'https://sqs.ap-northeast-1.amazonaws.com/111122223333/redmine-jobs-dlq'
  DLQ_ARN = 'arn:aws:sqs:ap-northeast-1:111122223333:redmine-jobs-dlq'

  def setup
    super
    @saved_url = ENV.fetch('REDMINE_JOBS_QUEUE_URL', nil)
    ENV['REDMINE_JOBS_QUEUE_URL'] = QUEUE_URL
    @config = Aws::ActiveJob::SQS.config
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
      visit '/admin/serverless/jobs'
      assert_selector '#serverless-job-failures'
      shoot 'jobs', language
    end
  end

  private

  def stub_client
    client = Aws::SQS::Client.new(stub_responses: true, region: 'ap-northeast-1')
    attributes = { 'QueueArn' => QUEUE_ARN, 'ApproximateNumberOfMessages' => '3',
                   'ApproximateNumberOfMessagesNotVisible' => '1', 'ApproximateNumberOfMessagesDelayed' => '0',
                   'RedrivePolicy' => { deadLetterTargetArn: DLQ_ARN, maxReceiveCount: 3 }.to_json }
    client.stub_responses(:get_queue_attributes, lambda { |context|
      if context.params[:queue_url] == DLQ_URL
        { attributes: { 'ApproximateNumberOfMessages' => '2' } }
      else
        { attributes: attributes }
      end
    })
    client.stub_responses(:get_queue_url, queue_url: DLQ_URL)
    client
  end

  def record_failures
    now = Time.current
    [
      ['Mailer::DeliveryJob', 'Mailer#issue_edit', 'mailers', 'Net::ReadTimeout',
       'Net::ReadTimeout with #<TCPSocket:(closed)>', 3, 3.hours],
      ['DestroyProjectJob', 'DestroyProjectJob', 'default', 'ActiveRecord::StatementInvalid',
       'PG::QueryCanceled: ERROR:  canceling statement due to statement timeout', 3, 26.hours]
    ].each_with_index do |(job_class, summary, queue, error, message, attempts, ago), index|
      ServerlessJobFailure.create!(
        job_class: job_class, job_id: SecureRandom.uuid, queue_name: queue, summary: summary,
        job_data: { job_class: job_class, arguments: [] }.to_json,
        error_class: error, error_message: message, attempts: attempts,
        enqueued_at: now - ago - 10.minutes, failed_at: now - ago + index.minutes
      )
    end
  end
end
