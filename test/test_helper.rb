# frozen_string_literal: true

# Coverage of the plugin's own files (bin/test sets PLUGIN_COVERAGE for the
# plugin's tests), written as Cobertura XML to coverage/ for Codecov. It starts
# before Redmine loads, so that boot/, lib/ and app/ are counted.
if ENV['PLUGIN_COVERAGE']
  require 'simplecov'
  require 'simplecov-cobertura'
  SimpleCov.start do
    root File.expand_path('..', __dir__)
    add_filter '/test/'
    enable_coverage :branch
    formatter SimpleCov::Formatter::CoberturaFormatter
  end
end

require File.expand_path('../../../test/test_helper', __dir__)

module RedmineAwsSqs
  module TestHelper
    QUEUE_URL = 'https://sqs.us-east-1.amazonaws.com/123456789012/redmine-jobs'
    QUEUE_ARN = 'arn:aws:sqs:us-east-1:123456789012:redmine-jobs'
    DLQ_URL = 'https://sqs.us-east-1.amazonaws.com/123456789012/redmine-jobs-dlq'
    DLQ_ARN = 'arn:aws:sqs:us-east-1:123456789012:redmine-jobs-dlq'

    # Runs the block with REDMINE_JOBS_QUEUE_URL set (or unset with nil).
    def with_queue_url(url)
      saved = ENV.fetch('REDMINE_JOBS_QUEUE_URL', nil)
      url ? ENV['REDMINE_JOBS_QUEUE_URL'] = url : ENV.delete('REDMINE_JOBS_QUEUE_URL')
      yield
    ensure
      saved ? ENV['REDMINE_JOBS_QUEUE_URL'] = saved : ENV.delete('REDMINE_JOBS_QUEUE_URL')
    end

    # Runs the block with the adapter's client replaced by one with SDK
    # response stubs.
    def with_sqs_client(client)
      config = Aws::ActiveJob::SQS.config
      saved = config.client
      config.client = client
      yield client
    ensure
      config.client = saved
    end

    def stub_client(dead_letter: true, waiting: 3, dead: 2)
      client = Aws::SQS::Client.new(stub_responses: true)
      attributes = { 'QueueArn' => QUEUE_ARN, 'ApproximateNumberOfMessages' => waiting.to_s,
                     'ApproximateNumberOfMessagesNotVisible' => '1', 'ApproximateNumberOfMessagesDelayed' => '0' }
      attributes['RedrivePolicy'] = { deadLetterTargetArn: DLQ_ARN, maxReceiveCount: 3 }.to_json if dead_letter
      client.stub_responses(:get_queue_attributes, lambda { |context|
        if context.params[:queue_url] == DLQ_URL
          { attributes: { 'ApproximateNumberOfMessages' => dead.to_s } }
        else
          { attributes: attributes }
        end
      })
      client.stub_responses(:get_queue_url, queue_url: DLQ_URL)
      client
    end

    # The body that the adapter writes for a job.
    def job_body(job)
      ActiveSupport::JSON.dump(job.serialize)
    end

    # An SQS event as Lambda gives it to the handler, for one message.
    def lambda_event(body, receives: 1, arn: QUEUE_ARN)
      { 'Records' => [{
        'messageId' => SecureRandom.uuid, 'receiptHandle' => 'handle', 'body' => body,
        'attributes' => { 'ApproximateReceiveCount' => receives.to_s,
                          'SentTimestamp' => (Time.now.to_f * 1000).to_i.to_s },
        'messageAttributes' => {}, 'md5OfBody' => Digest::MD5.hexdigest(body),
        'eventSource' => 'aws:sqs', 'eventSourceARN' => arn, 'awsRegion' => 'us-east-1'
      }] }
    end
  end
end
