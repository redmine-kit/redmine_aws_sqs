# frozen_string_literal: true

module RedmineAws
  module SQS
    # Redmine reloads its settings after an administrator changes them only
    # at the start of a web request (ApplicationController calls
    # Setting.check_cache). A process that runs jobs from the job queue, on
    # Lambda or with the gem's poller, stays up between jobs, so every job
    # does the same first (a before_perform callback of ActiveJob::Base),
    # while the job queue is on: jobs such as email use the current settings.
    module SettingsCheck
      extend ActiveSupport::Concern

      included do
        before_perform :check_redmine_settings
      end

      def self.install
        ::ActiveJob::Base.include(self) unless ::ActiveJob::Base.include?(self)
      end

      private

      def check_redmine_settings
        Setting.check_cache if RedmineAws::SQS.enabled?
      end
    end
  end
end
