# frozen_string_literal: true

# The part of Redmine AWS SQS that must be in place before Rails finishes
# initializing: the queue adapter and the settings of aws-activejob-sqs.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads. It
# defines only RedmineAws::SQS::Boot: the modules around it are empty here,
# and lib/redmine_aws.rb and lib/redmine_aws/sqs.rb, which the code loader
# then skips, are loaded by the init.rb files. The module names of
# redmine_aws come first: with RedmineAws defined, the code loader names the
# files under lib/redmine_aws/ while it sets up.
require 'redmine_aws/inflections'
require 'aws-activejob-sqs'

module RedmineAws
  module SQS
    module Boot
      # Redmine's own jobs (Mailer::DeliveryJob sends every email), and the jobs
      # of the other Redmine AWS plugins, so that they run whatever the order the
      # plugins load in. Other plugins add theirs with allow_job.
      JOBS = %w[Mailer::DeliveryJob DestroyProjectJob DestroyProjectsJob WebhookJob
                AwsS3ReconcileJob AwsSesReimportMailJob].freeze
      QUEUES = %i[default mailers].freeze

      @allowed_jobs = JOBS.dup

      class << self
        attr_reader :allowed_jobs

        def queue_url
          url = ENV.fetch('REDMINE_JOBS_QUEUE_URL', '')
          url.empty? ? nil : url
        end

        def enabled?
          !queue_url.nil?
        end

        # Adds a job class that may run from the queue. Plugins call it from
        # init.rb; a later call also updates the settings in place.
        def allow_job(class_name)
          @allowed_jobs |= [class_name.to_s]
          configure if enabled? && Rails.application&.initialized?
        end

        # Every queue Redmine uses goes to the one job queue, and only the allowed
        # job classes run, whatever a message names.
        def configure
          ::Aws::ActiveJob::SQS.configure do |config|
            config.queues = QUEUES.to_h { |queue| [queue, { url: queue_url }] }
            config.job_class_allowlist = allowed_jobs.dup
          end
        end
      end

      if defined?(Rails::Railtie)
        class Railtie < Rails::Railtie
          # Before ActiveJob copies its settings to ActiveJob::Base.
          initializer 'redmine_aws_sqs.queue_adapter', before: 'active_job.set_configs' do |app|
            app.config.active_job.queue_adapter = :sqs if RedmineAws::SQS::Boot.enabled?
          end

          # After the plugins' init.rb files, which may add job classes.
          config.after_initialize do
            RedmineAws::SQS::Boot.configure if RedmineAws::SQS::Boot.enabled?
          end
        end
      end
    end
  end
end
