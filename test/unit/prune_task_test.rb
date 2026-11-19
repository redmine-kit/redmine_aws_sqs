# frozen_string_literal: true

require_relative '../test_helper'
require 'rake'

module RedmineKit
  module Aws
    module Sqs
      # The rake task redmine_kit:aws:sqs:prune, with DAYS as Serverless's
      # daily schedule passes it.
      class PruneTaskTest < ActiveSupport::TestCase
        include RedmineKit::Aws::Sqs::TestHelper

        setup do
          Rails.application.load_tasks unless Rake::Task.task_defined?('redmine_kit:aws:sqs:prune')
          { 'Old' => 91, 'Month' => 31, 'New' => 0 }.each do |name, days|
            failure = AwsSqsJobFailure.record!('{}', RuntimeError.new(name), attempts: 1)
            failure.update_columns(failed_at: days.days.ago, job_class: "#{name}Job")
          end
        end

        # The output, or the SystemExit of abort.
        def rake_prune(env)
          task = Rake::Task['redmine_kit:aws:sqs:prune']
          task.reenable
          with_env({ 'DAYS' => nil }.merge(env)) { capture_io { task.invoke } }
        end

        def kept
          AwsSqsJobFailure.order(:job_class).pluck(:job_class)
        end

        def test_the_task_is_in_the_redmine_kit_namespace
          assert Rake::Task.task_defined?('redmine_kit:aws:sqs:prune')
          assert_empty Rake::Task.tasks.map(&:name).grep(/\Aredmine_kit_aws_sqs:/)
          assert_empty Rake::Task['redmine_kit:aws:sqs:prune'].arg_names
        end

        def test_without_days_keeps_90_days
          out, = rake_prune({})

          assert_equal "deleted 1 record(s) older than 90 days\n", out
          assert_equal %w[MonthJob NewJob], kept
        end

        def test_days_sets_the_number_of_days
          out, = rake_prune('DAYS' => '30')

          assert_equal "deleted 2 record(s) older than 30 days\n", out
          assert_equal %w[NewJob], kept
        end

        def test_an_invalid_days_aborts_and_deletes_nothing
          ['', '0', '-1', 'abc', '30abc', '1.5', ' 30', "30\n", '100000'].each do |value|
            error = assert_raises(SystemExit, "DAYS=#{value.inspect}") { rake_prune('DAYS' => value) }

            assert_not error.success?
            assert_equal %w[MonthJob NewJob OldJob], kept, "DAYS=#{value.inspect}"
          end
        end

        def test_the_message_of_an_invalid_days
          assert_equal ['Invalid DAYS abc given. The value must be an integer from 1 to 99999.', false],
                       Tasks.prune('DAYS' => 'abc')
        end
      end
    end
  end
end
