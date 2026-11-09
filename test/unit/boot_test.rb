# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSqs
  class BootTest < ActiveSupport::TestCase
    include RedmineServerlessSqs::TestHelper

    def test_off_without_the_queue_url
      with_queue_url(nil) do
        assert_not RedmineServerlessSqsBoot.enabled?
        assert_not RedmineServerlessSqs.enabled?
      end
    end

    def test_every_queue_goes_to_the_job_queue
      with_queue_url(QUEUE_URL) do
        RedmineServerlessSqsBoot.configure
        config = Aws::ActiveJob::SQS.config

        assert_equal QUEUE_URL, config.url_for(:default)
        assert_equal QUEUE_URL, config.url_for(:mailers)
      end
    end

    def test_only_redmine_jobs_are_allowed
      with_queue_url(QUEUE_URL) do
        RedmineServerlessSqsBoot.configure
        allowlist = Array(Aws::ActiveJob::SQS.config.job_class_allowlist).map(&:to_s)

        assert_includes allowlist, Mailer.delivery_job.name
        assert_includes allowlist, 'DestroyProjectJob'
        assert_includes allowlist, 'DestroyProjectsJob'
        assert_includes allowlist, 'WebhookJob'
        assert_not_includes allowlist, 'ActiveJob::Base'
      end
    end

    def test_a_plugin_adds_a_job_class
      with_queue_url(QUEUE_URL) do
        RedmineServerlessSqsBoot.allow_job('RedmineServerlessSqsTestJob')

        assert_includes Array(Aws::ActiveJob::SQS.config.job_class_allowlist).map(&:to_s),
                        'RedmineServerlessSqsTestJob'
      end
    end
  end
end
