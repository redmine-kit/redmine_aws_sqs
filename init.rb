# frozen_string_literal: true

# Redmine runs this when it prepares the code. The queue adapter and the
# settings of aws-activejob-sqs are in boot/redmine_aws_sqs.rb, which
# Bundler loads earlier.

# Redmine's code loader (Zeitwerk) skips lib/redmine_aws/sqs.rb when
# RedmineAws::SQS is already defined, as it is when Bundler has loaded
# boot/redmine_aws_sqs.rb. The file is then loaded here.
require File.expand_path('lib/redmine_aws/sqs', __dir__) unless defined?(RedmineAws::SQS::VERSION)

Redmine::Plugin.register :redmine_aws_sqs do
  # First, so that Redmine names a missing redmine_aws before anything uses it.
  requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'
  name 'Redmine AWS SQS'
  author 'Redmine Kit'
  description "Runs Redmine's jobs on Amazon SQS"
  version RedmineAws::SQS::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_sqs'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
end

RedmineAws::SQS.setup
