# frozen_string_literal: true

# Redmine Kit AWS SQS as a gem (docs/setup.md#installation): Bundler requires this file
# when Redmine's Gemfile.local has `gem 'redmine_kit_aws_sqs'`, or (with a checkout in
# plugins/) the plugin's Gemfile names it by path.
#
# Redmine 7.0.3 loads plugins from its plugins/ folder only
# (Redmine::PluginLoader). This hands the gem's folder to the same loader,
# after Redmine's initializers have listed plugins/: Redmine then runs
# init.rb (which registers the plugin with this folder, `directory`) and
# serves its assets, locales, views and migrations as for any plugin; the
# folder's lib/ and app/ go to Rails' code loader (Zeitwerk) as Redmine adds a
# plugin's (PluginLoader.add_autoload_paths); its routes come after Redmine's,
# as Redmine draws a plugin's. A plugin of the same id in plugins/ (a checkout
# or a link) wins, and nothing is done (redmine_kit_ui's template,
# examples/redmine_kit_example).
#
# The part of Redmine Kit AWS SQS that must be in place before Rails finishes
# initializing: the queue adapter and the settings of aws-activejob-sqs.
# Bundler loads this file (the plugin is also a gem); init.rb, which Redmine
# runs later, does the rest. It is outside lib/, which Redmine autoloads. It
# defines only RedmineKit::Aws::Sqs::Boot: the modules around it are empty
# and nested here (RedmineKit belongs to no plugin), and lib/redmine_kit/aws.rb
# and lib/redmine_kit/aws/sqs.rb, which the code loader then skips, are
# loaded by the init.rb files.
require 'aws-activejob-sqs'

require 'active_support/lazy_load_hooks'
# The gems of the plugins it requires (config/dependencies.yml): Bundler
# installs them with this one, and their boot files hand their folders to
# Redmine's plugin loader too.
require 'yaml'
YAML.safe_load_file(File.expand_path('../config/dependencies.yml', __dir__))['requires'].each_key do |name|
  require name
end

ActiveSupport.on_load(:before_configuration, yield: true) do |app|
  dir = File.expand_path('..', __dir__)
  app.initializer 'redmine_kit_aws_sqs.gem', after: :load_config_initializers do |application|
    loader = Redmine::PluginLoader
    next if loader.directories.any? { |path| File.basename(path.to_s) == 'redmine_kit_aws_sqs' }

    loader.directories << Redmine::PluginPath.new(dir)
    Rails::Engine::Configuration.new(dir).tap { |config| config.paths.add 'lib', eager_load: true }
                                .all_eager_load_paths.each do |path|
      Rails.autoloaders.main.push_dir(path)
      application.config.watchable_dirs[path] = [:rb]
    end
    routes = File.join(dir, 'config/routes.rb')
    application.routes.append { instance_eval(File.read(routes), routes) } if File.file?(routes)
  end
end

module RedmineKit
  module Aws
    module Sqs
      module Boot
        # Redmine's own jobs (Mailer::DeliveryJob sends every email), and the jobs
        # of the other Redmine Kit AWS plugins, so that they run whatever the order the
        # plugins load in. Other plugins add theirs with allow_job.
        JOBS = %w[Mailer::DeliveryJob DestroyProjectJob DestroyProjectsJob WebhookJob
                  AwsS3ReconcileJob AwsSesReimportMailJob].freeze
        QUEUES = %i[default mailers].freeze

        @allowed_jobs = JOBS.dup

        class << self
          attr_reader :allowed_jobs

          def queue_url
            url = ENV.fetch('REDMINE_SQS_QUEUE_URL', '')
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
            initializer 'redmine_kit_aws_sqs.queue_adapter', before: 'active_job.set_configs' do |app|
              app.config.active_job.queue_adapter = :sqs if RedmineKit::Aws::Sqs::Boot.enabled?
            end

            # After the plugins' init.rb files, which may add job classes.
            config.after_initialize do
              RedmineKit::Aws::Sqs::Boot.configure if RedmineKit::Aws::Sqs::Boot.enabled?
            end
          end
        end
      end
    end
  end
end
