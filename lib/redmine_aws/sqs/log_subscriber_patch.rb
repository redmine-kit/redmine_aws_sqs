# frozen_string_literal: true

module RedmineAws
  module SQS
    # Prepended to ActiveJob::LogSubscriber. Its private args_info adds
    # " with arguments: …" to the "Enqueued" and "Performing" lines with every
    # argument as it is, so that the password of Mailer#account_information
    # reaches the log (on Lambda, CloudWatch Logs). With the job queue on, the
    # arguments are described by JobDescription instead, with secrets
    # filtered; without it, Redmine logs as standard. The log subscriber test
    # fails if Rails stops building the line in args_info.
    module LogSubscriberPatch
      def self.install
        ::ActiveJob::LogSubscriber.prepend(self) unless ::ActiveJob::LogSubscriber.include?(self)
      end

      private

      def args_info(job)
        return super unless RedmineAws::SQS.enabled? && job.class.log_arguments? && job.arguments.any?

        " with arguments: #{JobDescription.from_job(job).call}"
      end
    end
  end
end
