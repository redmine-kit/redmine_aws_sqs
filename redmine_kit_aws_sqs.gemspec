# frozen_string_literal: true

require 'yaml'

# The plugin as a gem, published to GitHub Packages (.github/workflows/gem.yml).
# The gem holds the plugin's run-time files, so that the installed gem can be
# linked into Redmine's plugins/ (docs/setup.md#installation). The plugin's
# Gemfile is not in it: Redmine's Gemfile would load it again.
Gem::Specification.new do |spec|
  spec.name = 'redmine_kit_aws_sqs'
  spec.version = File.read(File.join(__dir__, 'lib/redmine_kit/aws/sqs.rb'))[/VERSION = '([^']+)'/, 1]
  spec.summary = "Runs Redmine's jobs on Amazon SQS"
  spec.authors = ['Redmine Kit']
  spec.license = 'GPL-2.0-or-later'
  spec.homepage = 'https://github.com/redmine-kit/redmine_aws_sqs'
  # The Ruby versions of Redmine 7.0 (its Gemfile: ruby '>= 3.2.0', '< 4.1.0').
  spec.required_ruby_version = ['>= 3.2', '< 4.1']
  spec.files = Dir['{init.rb,LICENSE}', '{app,boot,config,db,lib,help}/**/*']
  # boot/ holds what Bundler loads before Rails initializes; lib/ is Redmine's
  # (autoloaded) and must not be required by Bundler.
  spec.require_paths = ['boot']
  spec.add_dependency 'aws-activejob-sqs', '~> 1.2'
  spec.add_dependency 'aws-sdk-sqs', '~> 1.0'
  spec.metadata['github_repo'] = 'ssh://github.com/redmine-kit/redmine_aws_sqs'
  # The plugins it requires (config/dependencies.yml): installing the gem installs them.
  YAML.safe_load_file(File.join(__dir__, 'config/dependencies.yml'))['requires'].each do |name, range|
    spec.add_dependency name, range
  end
  spec.metadata['rubygems_mfa_required'] = 'true'
end
