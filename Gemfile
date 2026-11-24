# frozen_string_literal: true

# Loaded by Redmine's Gemfile when the plugin is a checkout in plugins/. To
# load boot/redmine_kit_aws_sqs.rb (the queue adapter), add the plugin as a gem by
# path in Gemfile.local instead (docs/setup.md#installation); the gem's
# dependencies are then in the gemspec.
gem 'aws-activejob-sqs', '~> 1.2'

# A checkout in Redmine's plugins/: the plugin as a gem by its path, so that
# Bundler loads boot/redmine_kit_aws_sqs.rb before Rails initializes, as the installed gem
# does (Redmine runs init.rb too late for what boot/ sets), and Redmine Kit
# AWS, which its gemspec requires, from its checkout next to it; each unless
# Gemfile.local or another plugin's Gemfile names it already.
unless dependencies.any? { |dependency| dependency.name == 'redmine_kit_aws' }
  gem 'redmine_kit_aws', path: File.expand_path('../redmine_kit_aws', __dir__), require: false
end
unless dependencies.any? { |dependency| dependency.name == 'redmine_kit_aws_sqs' }
  gem 'redmine_kit_aws_sqs', path: __dir__
end
