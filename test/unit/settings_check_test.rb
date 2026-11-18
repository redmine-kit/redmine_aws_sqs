# frozen_string_literal: true

require_relative '../test_helper'

# A job that does nothing, for the settings check.
class RedmineKitAwsSqsSettingsTestJob < ActiveJob::Base
  def perform; end
end

module RedmineKit
  module Aws
    module Sqs
      # Every job checks Redmine's settings first while the job queue is on,
      # whichever way it runs (Lambda or the poller), as each web request does.
      class SettingsCheckTest < ActiveSupport::TestCase
        include RedmineKit::Aws::Sqs::TestHelper

        def test_each_job_checks_the_settings
          with_queue_url(QUEUE_URL) do
            Setting.expects(:check_cache).once

            RedmineKitAwsSqsSettingsTestJob.perform_now
          end
        end

        def test_not_without_the_job_queue
          with_queue_url(nil) do
            Setting.expects(:check_cache).never

            RedmineKitAwsSqsSettingsTestJob.perform_now
          end
        end
      end
    end
  end
end
