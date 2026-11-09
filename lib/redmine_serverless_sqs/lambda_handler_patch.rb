# frozen_string_literal: true

module RedmineServerlessSqs
  # Prepended to aws-activejob-sqs's Lambda handler, which runs one message
  # per invocation (batch size 1, docs/setup.md#aws-resources). Failures are
  # recorded as Failures describes:
  #
  # - The error of a job is raised again after recording, so that SQS
  #   retries the message, and moves it to the dead-letter queue after the
  #   last receive.
  # - A message that can never run is recorded and not retried: the
  #   invocation succeeds, so Lambda deletes the message.
  module LambdaHandlerPatch
    def job_handler(event:, context:)
      super
    rescue Aws::ActiveJob::SQS::InvalidJobClassError, JSON::ParserError => e
      records = Array(event['Records'])
      records.each { |record| Failures.record(record['body'], e, **LambdaHandlerPatch.details(record)) }
      "Dropped #{records.size} job(s): #{e.message}"
    rescue StandardError => e
      Array(event['Records']).each do |record|
        Failures.record_if_last(record['body'], e, **LambdaHandlerPatch.details(record))
      end
      raise
    end

    def self.install
      handler = Aws::ActiveJob::SQS::LambdaHandler.singleton_class
      handler.prepend(self) unless handler.include?(self)
    end

    def self.details(record)
      attributes = record['attributes'] || {}
      { receives: attributes['ApproximateReceiveCount'].to_i, sent_at: attributes['SentTimestamp'] }
    end
  end
end
