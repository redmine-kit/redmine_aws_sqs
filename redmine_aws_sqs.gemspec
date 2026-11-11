# frozen_string_literal: true

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_aws_sqs'
  spec.version = File.read(File.join(__dir__, 'lib/redmine_aws/sqs.rb'))[/VERSION = '([^']+)'/, 1]
  spec.summary = "Runs Redmine's jobs on Amazon SQS"
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_aws_sqs'
  # The Ruby versions of Redmine 7.0 (its Gemfile: ruby '>= 3.2.0', '< 4.1.0').
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['{init.rb,LICENSE}', '{app,boot,config,db,lib,help}/**/*']
  # boot/ holds what Bundler loads before Rails initializes; lib/ is Redmine's
  # (autoloaded) and must not be required by Bundler.
  spec.require_paths = ['boot']
  spec.add_dependency 'aws-activejob-sqs', '~> 1.2'
  spec.add_dependency 'aws-sdk-sqs', '~> 1.0'
  spec.add_dependency 'redmine_aws', '~> 0.1'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_aws_sqs'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
