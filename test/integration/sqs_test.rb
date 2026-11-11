# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAwsSqs
  # On moto: Redmine's jobs go to SQS through the adapter, and the handler
  # that Lambda calls runs them from the messages.
  class SqsTest < ActiveSupport::TestCase
    include RedmineAwsSqs::TestHelper

    def setup
      # An explicit endpoint, so that the queue URLs that the handler builds
      # from the ARN (sqs.<region>.amazonaws.com) still go to moto.
      @client = Aws::SQS::Client.new(endpoint: ENV.fetch('AWS_ENDPOINT_URL'))
      name = "redmine-jobs-#{SecureRandom.hex(4)}"
      @dlq_url = @client.create_queue(queue_name: "#{name}-dlq").queue_url
      policy = { deadLetterTargetArn: arn(@dlq_url), maxReceiveCount: 2 }.to_json
      @queue_url = @client.create_queue(queue_name: name, attributes: { 'RedrivePolicy' => policy }).queue_url
      @saved_url = ENV.fetch('REDMINE_JOBS_QUEUE_URL', nil)
      ENV['REDMINE_JOBS_QUEUE_URL'] = @queue_url
      Aws::ActiveJob::SQS.config.client = @client
      RedmineAwsSqsBoot.configure
      @saved_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :sqs
      ActionMailer::Base.deliveries.clear
    end

    def teardown
      ActiveJob::Base.queue_adapter = @saved_adapter
      @saved_url ? ENV['REDMINE_JOBS_QUEUE_URL'] = @saved_url : ENV.delete('REDMINE_JOBS_QUEUE_URL')
      [@queue_url, @dlq_url].compact.each { |url| @client.delete_queue(queue_url: url) }
    end

    def arn(url)
      @client.get_queue_attributes(queue_url: url, attribute_names: ['QueueArn']).attributes['QueueArn']
    end

    # Receives one message and gives it to the handler as Lambda would.
    def run_next_job
      message = @client.receive_message(queue_url: @queue_url, max_number_of_messages: 1,
                                        attribute_names: ['All'], wait_time_seconds: 1).messages.first
      assert message, 'no message in the job queue'
      event = lambda_event(message.body, receives: message.attributes['ApproximateReceiveCount'].to_i,
                                         arn: arn(@queue_url))
      event['Records'][0]['receiptHandle'] = message.receipt_handle
      # The message is deleted at REDMINE_JOBS_QUEUE_URL (the backend's), not at
      # the public host the gem builds from the ARN.
      Aws::ActiveJob::SQS::LambdaHandler.job_handler(event: event, context: nil)
    end

    def waiting(url = @queue_url)
      @client.get_queue_attributes(queue_url: url, attribute_names: ['ApproximateNumberOfMessages'])
             .attributes['ApproximateNumberOfMessages'].to_i
    end

    def test_a_notification_mail_goes_through_sqs
      Mailer.test_email(User.find(1)).deliver_later

      assert_empty ActionMailer::Base.deliveries
      assert_equal 1, waiting
      run_next_job

      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_equal 0, waiting
    end

    def test_a_job_class_outside_the_allowlist_is_not_run
      @client.send_message(queue_url: @queue_url,
                           message_body: { job_class: 'RedmineAwsSqsNotAllowedJob', job_id: '1',
                                           arguments: [] }.to_json)

      assert_difference('AwsSqsJobFailure.count', 1) { run_next_job }
    end

    def test_a_recorded_job_is_resent_and_runs
      Mailer.test_email(User.find(1)).deliver_later
      body = @client.receive_message(queue_url: @queue_url, wait_time_seconds: 1).messages.first.body
      failure = AwsSqsJobFailure.record!(body, RuntimeError.new('boom'), attempts: 2)
      @client.purge_queue(queue_url: @queue_url)
      failure.resend!

      assert_equal 1, waiting
      run_next_job

      assert_equal 1, ActionMailer::Base.deliveries.size
    end

    def test_counts_from_the_redrive_policy
      @client.send_message(queue_url: @dlq_url, message_body: '{}')
      queue = RedmineAwsSqs::Queue.new(url: @queue_url, client: @client)

      assert_equal 1, queue.counts[:dead_letter]
      assert_equal 2, queue.max_receives
    end

    # moto does not have StartMessageMoveTask (it answers 500); there, moving
    # the dead-letter queue back is covered by SDK response stubs (QueueTest).
    def test_moving_the_dead_letter_queue_back
      skip 'moto has no StartMessageMoveTask' unless ENV['TEST_AWS_BACKEND'] == 'localstack'

      @client.send_message(queue_url: @dlq_url, message_body: '{}')
      queue = RedmineAwsSqs::Queue.new(url: @queue_url, client: @client)

      assert queue.redrive
      moved = 20.times.any? do
        sleep 0.5
        waiting == 1 && waiting(@dlq_url).zero?
      end

      assert moved, 'the message did not move back to the job queue'
    end

    def test_the_connection_check
      results = RedmineAws::Admin.run_checks.index_by(&:name)

      assert results['sqs'].ok, results['sqs'].detail
      assert_match(/\Aredmine-jobs-\h+ \(Messages available: 0\)\z/, results['sqs'].detail)
    end
  end
end
