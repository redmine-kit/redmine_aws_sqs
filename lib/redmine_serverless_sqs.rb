# frozen_string_literal: true

# Redmine's background jobs on Amazon SQS (docs/README.md). On with
# REDMINE_JOBS_QUEUE_URL; boot/redmine_serverless_sqs.rb sets the queue
# adapter and the settings of aws-activejob-sqs.
module RedmineServerlessSqs
  VERSION = '0.1.3'

  def self.enabled?
    defined?(RedmineServerlessSqsBoot) ? RedmineServerlessSqsBoot.enabled? : false
  end

  # Called from init.rb, on every code reload.
  def self.setup
    LambdaHandlerPatch.install
    Failures.install_poller_handlers
    RedmineServerlessAdmin.register_tab(:jobs, label: :label_serverless_jobs,
                                               url: { controller: 'serverless_jobs', action: 'index' },
                                               position: 20)
    RedmineServerlessAdmin.register_check(:sqs, label: :label_serverless_check_sqs) do
      enabled? ? Queue.new.check : raise(ArgumentError, 'REDMINE_JOBS_QUEUE_URL is not set')
    end
  end
end
