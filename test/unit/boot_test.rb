# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    class BootTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def test_off_without_the_queue_url
        with_queue_url(nil) do
          assert_not RedmineAws::SQS::Boot.enabled?
          assert_not RedmineAws::SQS.enabled?
        end
      end

      def test_every_queue_goes_to_the_job_queue
        with_queue_url(QUEUE_URL) do
          RedmineAws::SQS::Boot.configure
          config = ::Aws::ActiveJob::SQS.config

          assert_equal QUEUE_URL, config.url_for(:default)
          assert_equal QUEUE_URL, config.url_for(:mailers)
        end
      end

      def test_only_redmine_jobs_are_allowed
        with_queue_url(QUEUE_URL) do
          RedmineAws::SQS::Boot.configure
          allowlist = Array(::Aws::ActiveJob::SQS.config.job_class_allowlist).map(&:to_s)

          [Mailer.delivery_job.name, 'DestroyProjectJob', 'DestroyProjectsJob', 'WebhookJob', 'AwsS3ReconcileJob',
           'AwsSesReimportMailJob'].each { |name| assert_includes allowlist, name }
          assert_not_includes allowlist, 'ActiveJob::Base'
        end
      end

      def test_a_plugin_adds_a_job_class
        with_queue_url(QUEUE_URL) do
          RedmineAws::SQS::Boot.allow_job('RedmineAwsSqsTestJob')

          assert_includes Array(::Aws::ActiveJob::SQS.config.job_class_allowlist).map(&:to_s),
                          'RedmineAwsSqsTestJob'
        end
      end
    end
  end
end
