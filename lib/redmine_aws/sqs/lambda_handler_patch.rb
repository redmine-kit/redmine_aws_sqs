# frozen_string_literal: true

module RedmineAws
  module SQS
    # Prepended to aws-activejob-sqs's Lambda handler, which runs one message
    # per invocation (batch size 1, docs/setup.md#aws-resources). Failures are
    # recorded as Failures describes:
    #
    # - The error of a job is raised again after recording, so that SQS
    #   retries the message, and moves it to the dead-letter queue after the
    #   last receive.
    # - A message that can never run is recorded and not retried: the
    #   invocation succeeds, so Lambda deletes the message.
    #
    # The gem's handler also writes the whole event to the function's log;
    # the patch writes that line without it (puts below).
    module LambdaHandlerPatch
      EVENT_LINE = 'job_handler running for '
      EVENT_LINE_WITHOUT_EVENT = 'job_handler running'

      # Aws::ActiveJob::SQS::LambdaHandler.job_handler, to record the
      # failures as above.
      def job_handler(event:, context:)
        super
      rescue ::Aws::ActiveJob::SQS::InvalidJobClassError, JSON::ParserError => e
        records = Array(event['Records'])
        records.each { |record| Failures.record(record['body'], e, **LambdaHandlerPatch.details(record)) }
        # The class only: a parser error's message quotes the body.
        "Dropped #{records.size} job(s): #{e.class.name}"
      rescue StandardError => e
        Array(event['Records']).each do |record|
          Failures.record_if_last(record['body'], e, **LambdaHandlerPatch.details(record))
        end
        raise
      end

      # REDMINE_JOBS_QUEUE_URL when the ARN names that queue (the same name,
      # the last part of both); nil otherwise.
      def self.configured_queue_url(arn)
        url = RedmineAws::SQS::Boot.queue_url
        name = arn.to_s.split(':').last
        url if url && name && !name.empty? && url.split('/').last == name
      end

      def self.install
        handler = ::Aws::ActiveJob::SQS::LambdaHandler.singleton_class
        handler.prepend(self) unless handler.include?(self)
      end

      def self.details(record)
        attributes = record['attributes'] || {}
        { receives: attributes['ApproximateReceiveCount'].to_i, sent_at: attributes['SentTimestamp'] }
      end

      private

      # Kernel#puts, as the gem's handler calls it. The handler writes
      # "job_handler running for <event>", and so every job's arguments
      # (Mailer#account_information's password among them), to the function's
      # log; that line is written without the event, the others as they are.
      # The lambda handler test fails if the gem changes the line.
      def puts(*lines)
        super(*lines.map { |line| line.to_s.start_with?(EVENT_LINE) ? EVENT_LINE_WITHOUT_EVENT : line })
      end

      # Aws::ActiveJob::SQS::LambdaHandler.to_queue_url (private): the URL at
      # which the gem deletes a message that ran. The gem builds it from the
      # event's ARN with the public SQS host, which an endpoint of another host
      # does not serve (LocalStack, or an interface endpoint without private
      # DNS); then the deletion fails after the job ran and the message runs
      # again. For the job queue, the URL Redmine sends jobs to
      # (REDMINE_JOBS_QUEUE_URL) is used instead; it is the same queue on AWS.
      # The lambda handler test fails if the gem stops deleting through it.
      def to_queue_url(record)
        LambdaHandlerPatch.configured_queue_url(record['eventSourceARN']) || super
      end
    end
  end
end
