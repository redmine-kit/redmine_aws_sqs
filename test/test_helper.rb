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
require File.join(Redmine::Plugin.find(:redmine_aws).directory, 'test/support/redmine_aws/test_helper')

module RedmineAws
  module SQS
    module TestHelper
      include RedmineAws::TestHelper

      QUEUE_URL = 'https://sqs.us-east-1.amazonaws.com/123456789012/redmine-jobs'
      QUEUE_ARN = 'arn:aws:sqs:us-east-1:123456789012:redmine-jobs'
      DLQ_URL = 'https://sqs.us-east-1.amazonaws.com/123456789012/redmine-jobs-dlq'
      DLQ_ARN = 'arn:aws:sqs:us-east-1:123456789012:redmine-jobs-dlq'

      # Runs the block with REDMINE_JOBS_QUEUE_URL set (or unset with nil).
      def with_queue_url(url, &)
        with_env({ 'REDMINE_JOBS_QUEUE_URL' => url }, &)
      end

      # Runs the block with the adapter's client replaced by one with SDK
      # response stubs.
      def with_sqs_client(client)
        config = ::Aws::ActiveJob::SQS.config
        saved = config.client
        config.client = client
        yield client
      ensure
        config.client = saved
      end

      def stub_client(dead_letter: true, waiting: 3, dead: 2)
        client = stub_aws_client(::Aws::SQS::Client)
        attributes = queue_attributes(dead_letter: dead_letter, waiting: waiting)
        dead_letter_attributes = { 'ApproximateNumberOfMessages' => dead.to_s }
        client.stub_responses(:get_queue_attributes, lambda { |context|
          { attributes: context.params[:queue_url] == DLQ_URL ? dead_letter_attributes : attributes }
        })
        client.stub_responses(:get_queue_url, queue_url: DLQ_URL)
        client
      end

      # The job queue's attributes, with a redrive policy to the dead-letter
      # queue or without one.
      def queue_attributes(dead_letter:, waiting:)
        attributes = { 'QueueArn' => QUEUE_ARN, 'ApproximateNumberOfMessages' => waiting.to_s,
                       'ApproximateNumberOfMessagesNotVisible' => '1', 'ApproximateNumberOfMessagesDelayed' => '0' }
        attributes['RedrivePolicy'] = { deadLetterTargetArn: DLQ_ARN, maxReceiveCount: 3 }.to_json if dead_letter
        attributes
      end

      # What the block writes to the logger of owner (Rails,
      # ActionController::Base, ActiveJob::Base).
      def capture_log(owner = Rails)
        io = StringIO.new
        saved = owner.logger
        owner.logger = ActiveSupport::Logger.new(io)
        yield
        io.string
      ensure
        owner.logger = saved
      end

      # A mail job, as Redmine's Mailer enqueues it.
      def mail_job(method, *args)
        Mailer.delivery_job.new('Mailer', method, 'deliver_now', args: args)
      end

      # The record of the job failing for the last time.
      def record_failure(job, error: RuntimeError.new('boom'))
        AwsSqsJobFailure.record!(job_body(job), error, attempts: 3, enqueued_at: 1.hour.ago)
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
end

module RedmineAws
  module SQS
    # AWS Emulator 1.0.322 answers queue URLs on the public SQS host
    # (https://sqs.<region>.amazonaws.com/...), which it does not serve, and
    # the SDK sends each request to the host of its queue URL. On the emulator
    # (TEST_AWS_BACKEND, set by bin/test), the queue URLs that it answers
    # (CreateQueue, GetQueueUrl, the lists) are put on the client's endpoint,
    # as AWS answers them on the endpoint the request went to. So
    # Queue#dead_letter_url gets the dead-letter queue on the emulator, as it
    # gets it on the configured endpoint on AWS (SqsTest, the counts). URLs
    # that the code builds itself keep the public host, which the internal
    # network does not reach: the message the gem would delete at the URL it
    # builds from the ARN stays, so SqsTest still checks that the deletion
    # uses REDMINE_JOBS_QUEUE_URL. The emulator's
    # issue: https://github.com/aws/aws-emulator/blob/7753983c6e495ec3612695b1336bf4936fc7b7fd/issues/things-that-do-not-work/20261109T191027Z-sqs-queue-url-addressing-diverges-from-aws-createqueue.md
    class EmulatorQueueUrls < Seahorse::Client::Plugin
      # Rewrites the queue URLs of a response; stubbed clients are left alone.
      class Handler < Seahorse::Client::Handler
        PUBLIC_HOST = %r{\Ahttps://sqs\.[^/]+\.amazonaws\.com(?=/)}

        def call(context)
          response = @handler.call(context)
          rewrite(response.data, context.config.endpoint.to_s.chomp('/')) if rewrite?(context, response)
          response
        end

        private

        def rewrite?(context, response)
          !context.config.stub_responses && response.successful?
        end

        def rewrite(data, endpoint)
          data.queue_url = data.queue_url.sub(PUBLIC_HOST, endpoint) if data.respond_to?(:queue_url=) && data.queue_url
          return unless data.respond_to?(:queue_urls=) && data.queue_urls

          data.queue_urls = data.queue_urls.map { |url| url.sub(PUBLIC_HOST, endpoint) }
        end
      end

      handler(Handler, step: :initialize)
    end
  end
end

Aws::SQS::Client.add_plugin(RedmineAws::SQS::EmulatorQueueUrls) if ENV['TEST_AWS_BACKEND'] == 'aws-emulator'
