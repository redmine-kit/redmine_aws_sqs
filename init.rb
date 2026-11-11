# frozen_string_literal: true

# Redmine runs this when it prepares the code. The queue adapter and the
# settings of aws-activejob-sqs are in boot/redmine_aws_sqs.rb, which
# Bundler loads earlier.
Redmine::Plugin.register :redmine_aws_sqs do
  name 'Redmine AWS SQS'
  author 'Redmine Kit'
  description "Runs Redmine's jobs on Amazon SQS"
  version RedmineAwsSqs::VERSION
  url 'https://github.com/redmine-kit/redmine_aws_sqs'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
  requires_redmine_plugin :redmine_aws, version_or_higher: '0.1.0'
end

RedmineAwsSqs.setup
