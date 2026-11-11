# frozen_string_literal: true

module RedmineAwsSqs
  # Records jobs that fail for the last time (AwsSqsJobFailure), for both
  # ways of running jobs: the Lambda handler (LambdaHandlerPatch) and the
  # gem's poller (the handlers below).
  #
  # - A job that raises is retried by SQS. It is recorded on the receive
  #   after which SQS moves the message to the dead-letter queue (the job
  #   queue's redrive policy, maxReceiveCount). Without a redrive policy, SQS
  #   keeps the message until its retention period ends, and nothing is
  #   recorded.
  # - A message that can never run (not JSON, or a job class outside the
  #   allowlist) is recorded at once and deleted.
  module Failures
    module_function

    def record_if_last(body, error, receives:, sent_at: nil)
      max = Queue.new.max_receives
      return if max.nil? || receives < max

      record(body, error, receives: receives, sent_at: sent_at)
    rescue StandardError => e
      # The message still goes to the dead-letter queue, which keeps it.
      Rails.logger.error "[redmine_aws_sqs] could not record a failed job: #{e.class}: #{e.message}"
    end

    # sent_at: SentTimestamp, in milliseconds.
    def record(body, error, receives:, sent_at: nil)
      AwsSqsJobFailure.record!(body, error, attempts: receives,
                                            enqueued_at: sent_at && Time.zone.at(sent_at.to_i / 1000.0))
    end

    # The poller's hooks, unless the application set its own. The poller
    # leaves a failed message for SQS to retry, and deletes a message that can
    # never run after the permanent failure handler.
    def install_poller_handlers(config = Aws::ActiveJob::SQS.config)
      config.poller_error_handler { |error, message| Failures.from_poller(message, error, last_only: true) } \
        unless config.poller_error_handler
      config.permanent_failure_handler { |error, message| Failures.from_poller(message, error, last_only: false) } \
        unless config.permanent_failure_handler
    end

    def from_poller(message, error, last_only:)
      data = message.data
      receives = data.attributes.to_h['ApproximateReceiveCount'].to_i
      sent_at = data.attributes.to_h['SentTimestamp']
      if last_only
        record_if_last(data.body, error, receives: receives, sent_at: sent_at)
      else
        record(data.body, error, receives: receives, sent_at: sent_at)
      end
    end
  end
end
