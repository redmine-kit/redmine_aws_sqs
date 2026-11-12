# frozen_string_literal: true

module RedmineAws
  module SQS
    # The job queue and its dead-letter queue. The dead-letter queue and the
    # number of receives before a message moves there come from the job queue's
    # redrive policy (docs/setup.md#configuration).
    class Queue
      COUNTS = {
        'ApproximateNumberOfMessages' => :waiting,
        'ApproximateNumberOfMessagesNotVisible' => :running,
        'ApproximateNumberOfMessagesDelayed' => :delayed
      }.freeze
      CACHE_SECONDS = 60

      def initialize(url: RedmineAws::SQS::Boot.queue_url, client: nil)
        @url = url
        @client = client
      end

      def client
        @client ||= ::Aws::ActiveJob::SQS.config.client
      end

      def attributes
        @attributes ||= client.get_queue_attributes(queue_url: @url, attribute_names: ['All']).attributes
      end

      def arn
        attributes['QueueArn']
      end

      def redrive_policy
        JSON.parse(attributes['RedrivePolicy'] || '{}')
      end

      # Receives before SQS moves a message to the dead-letter queue; nil
      # without a redrive policy.
      def max_receives
        redrive_policy['maxReceiveCount']&.to_i
      end

      def dead_letter_arn
        redrive_policy['deadLetterTargetArn']
      end

      def dead_letter_url
        return unless dead_letter_arn

        arn = ::Aws::ARNParser.parse(dead_letter_arn)
        client.get_queue_url(queue_name: arn.resource, queue_owner_aws_account_id: arn.account_id).queue_url
      end

      # Counts of the job queue and the dead-letter queue, cached for a minute
      # so that opening the page does not call SQS each time. The Jobs tab
      # reads them from SQS, an exception to "pages read stored data": the
      # counts are the queue's live state (docs/admin.md#jobs).
      def counts
        Rails.cache.fetch(['redmine_aws_sqs', 'counts', @url], expires_in: CACHE_SECONDS) do
          counts = COUNTS.to_h { |attribute, name| [name, attributes[attribute].to_i] }
          dead = dead_letter_url
          counts[:dead_letter] = dead && client.get_queue_attributes(
            queue_url: dead, attribute_names: ['ApproximateNumberOfMessages']
          ).attributes['ApproximateNumberOfMessages'].to_i
          counts
        end
      end

      # Moves the messages of the dead-letter queue back to the job queue.
      def redrive
        raise ArgumentError, 'the job queue has no dead-letter queue' unless dead_letter_arn

        client.start_message_move_task(source_arn: dead_letter_arn, destination_arn: arn).task_handle
      end

      def check
        available = attributes['ApproximateNumberOfMessages']
        "#{arn.split(':').last} (#{::I18n.t(:label_aws_sqs_jobs_waiting)}: #{available})"
      end

      # Sends a recorded message body back to the job queue as it was, with
      # the message attributes the adapter writes. Only an allowed job class is
      # sent; the job runner checks the class again when it receives it.
      def resend(body)
        name = JSON.parse(body)['job_class'].to_s
        raise ArgumentError, "#{name} is not an allowed job class" unless allowed?(name)

        attributes = {
          'aws_sqs_active_job_class' => { string_value: name, data_type: 'String' },
          'aws_sqs_active_job_version' => { string_value: ::Aws::ActiveJob::SQS::VERSION, data_type: 'String' }
        }
        client.send_message(queue_url: @url, message_body: body, message_attributes: attributes).message_id
      end

      private

      def allowed?(name)
        RedmineAws::SQS::Boot.allowed_jobs.include?(name)
      end
    end
  end
end
