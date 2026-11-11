# frozen_string_literal: true

# Redmine's background jobs on Amazon SQS (docs/README.md). On with
# REDMINE_JOBS_QUEUE_URL; boot/redmine_aws_sqs.rb sets the queue
# adapter and the settings of aws-activejob-sqs.
module RedmineAwsSqs
  VERSION = '0.1.0'

  def self.enabled?
    defined?(RedmineAwsSqsBoot) ? RedmineAwsSqsBoot.enabled? : false
  end

  # Called from init.rb, on every code reload.
  def self.setup
    LambdaHandlerPatch.install
    Failures.install_poller_handlers
    RedmineAws::Admin.register_tab(:jobs, label: :label_aws_sqs_jobs,
                                          url: { controller: 'aws_sqs_jobs', action: 'index' }, position: 20)
    RedmineAws::Admin.register_check(:sqs, label: :label_aws_sqs_check) do
      enabled? ? Queue.new.check : raise(ArgumentError, 'REDMINE_JOBS_QUEUE_URL is not set')
    end
  end
end
