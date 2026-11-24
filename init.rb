# frozen_string_literal: true

# The plugins this one requires (config/dependencies.yml): without one,
# Redmine stops here and names it.
load File.expand_path('config/dependencies.rb', __dir__)

# Redmine runs this when it prepares the code. The queue adapter and the
# settings of aws-activejob-sqs are in boot/redmine_kit_aws_sqs.rb, which
# Bundler loads earlier.

# Redmine's code loader (Zeitwerk) skips lib/redmine_kit/aws/sqs.rb when
# RedmineKit::Aws::Sqs is already defined, as it is when Bundler has loaded
# boot/redmine_kit_aws_sqs.rb. The file is then loaded here.
require File.expand_path('lib/redmine_kit/aws/sqs', __dir__) unless defined?(RedmineKit::Aws::Sqs::VERSION)

Redmine::Plugin.register :redmine_kit_aws_sqs do
  # This folder, as Redmine's plugin loader found it: plugins/redmine_kit_aws_sqs (a checkout
  # or a link), or the installed gem's folder (boot/redmine_kit_aws_sqs.rb). Redmine's
  # default is plugins/<id>, which a gem doesn't have.
  directory File.dirname(__FILE__)
  name 'Redmine Kit AWS SQS'
  author 'Redmine Kit'
  description "Runs Redmine's jobs on Amazon SQS"
  version RedmineKit::Aws::Sqs::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_sqs'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
end

RedmineKit::Aws::Sqs.setup
