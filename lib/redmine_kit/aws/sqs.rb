# frozen_string_literal: true

module RedmineKit
  module Aws
    # Redmine's background jobs on Amazon SQS (docs/README.md). On with
    # REDMINE_SQS_QUEUE_URL; boot/redmine_kit_aws_sqs.rb (RedmineKit::Aws::Sqs::Boot)
    # sets the queue adapter and the settings of aws-activejob-sqs.
    module Sqs
      VERSION = '0.1.0'

      def self.enabled?
        defined?(RedmineKit::Aws::Sqs::Boot) ? RedmineKit::Aws::Sqs::Boot.enabled? : false
      end

      # Called from init.rb, on every code reload; last, the other plugins'
      # registrations (their ActiveSupport.on_load(:redmine_kit_aws_sqs)
      # blocks: job classes), whatever order Redmine runs the plugins' init.rb in.
      def self.setup
        LambdaHandlerPatch.install
        SettingsCheck.install
        LogSubscriberPatch.install
        Failures.install_poller_handlers
        RedmineKit::Aws::Admin.register_tab(:jobs, label: :label_aws_sqs_jobs,
                                                   url: { controller: 'aws_sqs_jobs', action: 'index' }, position: 20)
        RedmineKit::Aws::Admin.register_check(:sqs, label: :label_aws_sqs_check) do
          enabled? ? Queue.new.check : raise(ArgumentError, 'REDMINE_SQS_QUEUE_URL is not set')
        end
        ActiveSupport.run_load_hooks(:redmine_kit_aws_sqs, self)
      end
    end
  end
end
