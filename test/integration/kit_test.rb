# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Sqs
      # The "Jobs" tab in Redmine Kit's new UI (redmine_kit_ui, installed by
      # bin/test's first run): the manifest it takes, and the tab's JSON and
      # actions of the browser's session (kit requests: the session and the
      # CSRF token), with SQS stubbed as the functional tests stub it.
      class KitTest < Redmine::IntegrationTest
        include RedmineKit::Aws::Sqs::TestHelper
        include RedmineKit::Ui::TestHelper if Redmine::Plugin.installed?(:redmine_kit_ui)

        fixtures :users, :email_addresses, :projects, :members, :member_roles, :roles

        def setup
          skip 'redmine_kit_ui is not installed (bin/test runs these with it)' unless kit_ui?
          User.current = nil
        end

        def teardown
          ActionController::Base.allow_forgery_protection = false
        end

        def kit_ui?
          Redmine::Plugin.installed?(:redmine_kit_ui)
        end

        test 'redmine_kit_ui takes the manifest: the tab Jobs of the page AWS' do
          screen = assert_kit_manifest(:redmine_kit_aws_sqs).screens.sole
          assert_equal({ path: '/admin/aws/jobs', component: 'AwsSqsJobs', layout: 'admin', menu_item: 'aws',
                         tab: 'label_aws_sqs_jobs', position: 20 },
                       screen.slice(:path, :component, :layout, :menu_item, :tab, :position))
        end

        test "the tab's JSON: the counts as the page shows them and the failed jobs" do
          record = record_failure(mail_job('account_information', User.find(2), 'pw-23'))
          other = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          with_queue_url(QUEUE_URL) do
            with_sqs_client(stub_client(waiting: 1234)) { AwsSqsSnapshot.refresh! }
            get '/admin/aws/jobs.json', headers: kit_session('admin', 'admin')
          end
          assert_response :success
          json = response.parsed_body
          assert json['enabled']
          assert json['dead_letter']
          assert_includes json['counts'], { 'name' => 'Messages available', 'value' => '1,234' }
          assert_equal [other.id, record.id].sort, json['failures'].pluck('id').sort
          row = json['failures'].detect { |failure| failure['id'] == record.id }
          assert_equal ['Mailer#account_information', 'RuntimeError', 3], row.values_at('summary', 'error', 'attempts')
          # Redmine's format_time, not the raw time
          assert_match(%r{\A[\d/.: -]+(AM|PM)?\z}, row['failed_at'])
          assert_not_includes response.body, 'pw-23'
        end

        test 'mail=1 lists the mail jobs only; without SQS, no counts' do
          record = record_failure(mail_job('account_information', User.find(2), 'pw-23'))
          record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          headers = kit_session('admin', 'admin')
          with_queue_url(nil) { get '/admin/aws/jobs.json', params: { mail: '1' }, headers: headers }
          json = response.parsed_body
          assert_equal [false, nil, nil], json.values_at('enabled', 'counts', 'updated')
          assert_equal [record.id], json['failures'].pluck('id')
        end

        test 'the actions need the CSRF token and a system administrator' do
          record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          headers = kit_session('admin', 'admin')
          post '/admin/aws/jobs/destroy.json', params: { ids: [record.id] }, headers: headers.except('X-CSRF-Token'),
                                               as: :json
          assert_response 422
          reset!
          # Redmine's login form, as the other sign-ins: kit_session turned the protection on
          ActionController::Base.allow_forgery_protection = false
          headers = kit_session('jsmith')
          get '/admin/aws/jobs.json', headers: headers
          assert_response :forbidden
          post '/admin/aws/jobs/destroy.json', params: { ids: [record.id] }, headers: headers, as: :json
          assert_response :forbidden
          assert AwsSqsJobFailure.exists?(record.id)
        end
      end
    end
  end
end
