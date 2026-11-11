# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # ActiveJob's "Enqueued" and "Performing" lines with the plugin's patch.
    class LogSubscriberPatchTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def account_information_job
        Mailer.delivery_job.new('Mailer', 'account_information', 'deliver_now', args: [User.find(2), 'pw-secret-20'])
      end

      # The log of performing the job, with the queue URL given (or nil).
      def performing_log(url)
        io = StringIO.new
        saved = ::ActiveJob::Base.logger
        ::ActiveJob::Base.logger = ActiveSupport::Logger.new(io)
        with_queue_url(url) { account_information_job.perform_now }
        io.string
      ensure
        ::ActiveJob::Base.logger = saved
      end

      def test_the_arguments_are_filtered
        log = performing_log(QUEUE_URL)

        assert_includes log, 'Performing Mailer::DeliveryJob'
        assert_includes log, " with arguments: Mailer#account_information(user: #{User.find(2).to_global_id}, " \
                             'password: [FILTERED])'
        assert_not_includes log, 'pw-secret-20'
      end

      # Off without the job queue: Redmine logs as standard.
      def test_standard_without_the_queue
        assert_includes performing_log(nil), 'pw-secret-20'
      end

      # The patch replaces Rails' private args_info; this fails if Rails stops
      # building the line there.
      def test_rails_builds_the_arguments_in_args_info
        assert_includes ::ActiveJob::LogSubscriber.private_instance_methods, :args_info
        assert_includes ::ActiveJob::LogSubscriber.ancestors, LogSubscriberPatch
      end
    end
  end
end
