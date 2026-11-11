# frozen_string_literal: true

require_relative '../test_helper'

class RedmineAwsSqsKeywordTestJob < ActiveJob::Base
  def perform(issue, token:, note: nil); end
end

module RedmineAws
  module SQS
    # How a job is described in the log: identifiers kept, secrets filtered.
    class JobDescriptionTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def setup
        RedmineAws::SQS::Boot.allow_job('RedmineAwsSqsKeywordTestJob')
      end

      def gid(record)
        record.to_global_id.to_s
      end

      def describe(job)
        JobDescription.from_body(job_body(job)).to_s
      end

      # Jobs that Redmine enqueues, and how their arguments are described.
      def known_jobs
        mail_jobs + [
          [DestroyProjectJob.new(1, 2, '127.0.0.1'), 'perform(project_id: 1, user_id: 2, remote_ip: "127.0.0.1")'],
          [RedmineAwsSqsKeywordTestJob.new(Issue.find(1), token: 'kw-secret-2', note: 'x' * 80),
           "perform(issue: #{gid(Issue.find(1))}, token: \"kw-secret-2\", note: \"#{'x' * 47}...\")"]
        ]
      end

      def mail_jobs
        user = User.find(2)
        token = Token.create!(user: user, action: 'recovery')
        [[mail_job('account_information', user, 'pw-secret-1'),
          "Mailer#account_information(user: #{gid(user)}, password: [FILTERED])"],
         [mail_job('issue_add', user, Issue.find(1)),
          "Mailer#issue_add(user: #{gid(user)}, issue: #{gid(Issue.find(1))})"],
         [mail_job('lost_password', user, token, 'jsmith@somenet.foo'),
          "Mailer#lost_password(user: #{gid(user)}, token: #{gid(token)}, recipient: \"jsmith@somenet.foo\")"]]
      end

      def test_jobs_are_described_with_their_parameter_names
        known_jobs.each do |job, call|
          assert_equal "#{job.class.name} (Job ID: #{job.job_id}) #{call}", describe(job)
        end
      end

      # Runs the block with the application's filter_parameters set to filters.
      def with_filter_parameters(filters)
        saved = Rails.application.config.filter_parameters
        Rails.application.config.filter_parameters = filters
        yield
      ensure
        Rails.application.config.filter_parameters = saved
      end

      # Mailer#account_information's password, whatever the application
      # filters.
      def test_the_password_is_filtered_without_the_application_filter
        description = with_filter_parameters([]) do
          describe(mail_job('account_information', User.find(2), 'pw-secret-3'))
        end

        assert_not_includes description, 'pw-secret-3'
        assert_includes description, 'password: [FILTERED]'
      end

      def test_the_application_filter_applies
        job = RedmineAwsSqsKeywordTestJob.new(Issue.find(1), token: 'kw-secret-4')
        description = with_filter_parameters(Rails.application.config.filter_parameters + [:token]) { describe(job) }

        assert_includes description, 'token: [FILTERED]'
      end

      # Bodies the queue may hold that do not match a job the plugin knows,
      # and their descriptions.
      def unknown_bodies
        user = User.find(2)
        [['not json {"password": "pw-secret-5"}', 'unknown (Job ID: ) perform()'],
         ['[1, 2]', 'unknown (Job ID: ) perform()'],
         [{ job_class: 'NotAllowedJob', job_id: '1',
            arguments: ['pw-secret-6', 7, { '_aj_globalid' => gid(user) }] }.to_json,
          "NotAllowedJob (Job ID: 1) perform(arg1: [FILTERED], arg2: 7, arg3: #{gid(user)})"],
         [{ job_class: '<script>', job_id: '1', arguments: ['pw-secret-7'] }.to_json,
          'unknown (Job ID: 1) perform(arg1: [FILTERED])']] + unknown_mail_bodies
      end

      def unknown_mail_bodies
        [['no_such_mail', ['Mailer', 'no_such_mail', 'deliver_now', { 'args' => ['pw-secret-8'] }],
          'Mailer#no_such_mail(arg1: [FILTERED])'],
         ['exit', ['Kernel', 'exit', 'deliver_now', { 'args' => ['pw-secret-9'] }], 'Kernel#exit(arg1: [FILTERED])'],
         ['x y', ['Mailer', 'x y', 'deliver_now', 'z'], 'Mailer#unknown()']].map do |_, arguments, call|
          [{ job_class: 'Mailer::DeliveryJob', job_id: '1', arguments: arguments }.to_json,
           "Mailer::DeliveryJob (Job ID: 1) #{call}"]
        end
      end

      # Nothing but identifiers reaches the log.
      def test_unknown_jobs_keep_identifiers_only
        unknown_bodies.each do |body, description|
          assert_equal description, JobDescription.from_body(body).to_s, body
        end
      end

      def test_a_job_that_cannot_be_serialized_is_described_without_arguments
        job = DestroyProjectJob.new(Object.new, 1, '127.0.0.1')

        assert_equal "DestroyProjectJob (Job ID: #{job.job_id}) perform()", JobDescription.from_job(job).to_s
      end
    end
  end
end
