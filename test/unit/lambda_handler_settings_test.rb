# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # A warm worker reloads Redmine's settings when they changed, as each web
    # request does (ApplicationController), at the start of each batch.
    class LambdaHandlerSettingsTest < ActiveSupport::TestCase
      def test_each_batch_checks_the_settings
        Setting.expects(:check_cache).once

        ::Aws::ActiveJob::SQS::LambdaHandler.job_handler(event: { 'Records' => [] }, context: nil)
      end
    end
  end
end
