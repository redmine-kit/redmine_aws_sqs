# frozen_string_literal: true

# Redmine runs this when it prepares the code. The queue adapter and the
# settings of aws-activejob-sqs are in boot/redmine_serverless_sqs.rb, which
# Bundler loads earlier.
Redmine::Plugin.register :redmine_serverless_sqs do
  name 'Redmine Serverless SQS'
  author 'Redmine Kit'
  description "Runs Redmine's jobs on Amazon SQS"
  version RedmineServerlessSqs::VERSION
  url 'https://github.com/redmine-kit/redmine_serverless_sqs'
  author_url 'https://github.com/redmine-kit'
  requires_redmine version_or_higher: '7.0.0'
end

RedmineServerlessSqs.setup
