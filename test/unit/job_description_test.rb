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

      def mail_job(method, *args)
        Mailer.delivery_job.new('Mailer', method, 'deliver_now', args: args)
      end

      def describe(job)
        JobDescription.from_body(job_body(job)).to_s
      end

      def test_jobs_are_described_with_their_parameter_names
        user = User.find(2)
        issue = Issue.find(1)
        token = Token.create!(user: user, action: 'recovery')
        [
          [mail_job('account_information', user, 'pw-secret-1'),
           "Mailer#account_information(user: #{gid(user)}, password: [FILTERED])"],
          [mail_job('issue_add', user, issue), "Mailer#issue_add(user: #{gid(user)}, issue: #{gid(issue)})"],
          [mail_job('lost_password', user, token, 'jsmith@somenet.foo'),
           "Mailer#lost_password(user: #{gid(user)}, token: #{gid(token)}, recipient: \"jsmith@somenet.foo\")"],
          [DestroyProjectJob.new(1, 2, '127.0.0.1'),
           'perform(project_id: 1, user_id: 2, remote_ip: "127.0.0.1")'],
          [RedmineAwsSqsKeywordTestJob.new(issue, token: 'kw-secret-2', note: 'x' * 80),
           "perform(issue: #{gid(issue)}, token: \"kw-secret-2\", note: \"#{'x' * 47}...\")"]
        ].each do |job, call|
          assert_equal "#{job.class.name} (Job ID: #{job.job_id}) #{call}", describe(job)
        end
      end

      # Mailer#account_information's password, whatever the application
      # filters.
      def test_the_password_is_filtered_without_the_application_filter
        saved = Rails.application.config.filter_parameters
        Rails.application.config.filter_parameters = []
        body = job_body(mail_job('account_information', User.find(2), 'pw-secret-3'))

        assert_not_includes JobDescription.from_body(body).to_s, 'pw-secret-3'
        assert_includes JobDescription.from_body(body).to_s, 'password: [FILTERED]'
      ensure
        Rails.application.config.filter_parameters = saved
      end

      def test_the_application_filter_applies
        saved = Rails.application.config.filter_parameters
        Rails.application.config.filter_parameters += [:token]
        job = RedmineAwsSqsKeywordTestJob.new(Issue.find(1), token: 'kw-secret-4')

        assert_includes describe(job), 'token: [FILTERED]'
      ensure
        Rails.application.config.filter_parameters = saved
      end

      # Bodies the queue may hold that do not match a job the plugin knows:
      # nothing but identifiers reaches the log.
      def test_unknown_jobs_keep_identifiers_only
        user = User.find(2)
        [
          ['not json {"password": "pw-secret-5"}', 'unknown (Job ID: ) perform()'],
          ['[1, 2]', 'unknown (Job ID: ) perform()'],
          [{ job_class: 'NotAllowedJob', job_id: '1',
             arguments: ['pw-secret-6', 7, { '_aj_globalid' => gid(user) }] }.to_json,
           "NotAllowedJob (Job ID: 1) perform(arg1: [FILTERED], arg2: 7, arg3: #{gid(user)})"],
          [{ job_class: '<script>', job_id: '1', arguments: ['pw-secret-7'] }.to_json,
           'unknown (Job ID: 1) perform(arg1: [FILTERED])'],
          [{ job_class: 'Mailer::DeliveryJob', job_id: '1',
             arguments: ['Mailer', 'no_such_mail', 'deliver_now', { 'args' => ['pw-secret-8'] }] }.to_json,
           'Mailer::DeliveryJob (Job ID: 1) Mailer#no_such_mail(arg1: [FILTERED])'],
          [{ job_class: 'Mailer::DeliveryJob', job_id: '1',
             arguments: ['Kernel', 'exit', 'deliver_now', { 'args' => ['pw-secret-9'] }] }.to_json,
           'Mailer::DeliveryJob (Job ID: 1) Kernel#exit(arg1: [FILTERED])'],
          [{ job_class: 'Mailer::DeliveryJob', job_id: '1', arguments: ['Mailer', 'x y', 'deliver_now', 'z'] }.to_json,
           'Mailer::DeliveryJob (Job ID: 1) Mailer#unknown()']
        ].each do |body, description|
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
