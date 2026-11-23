# frozen_string_literal: true

require_relative '../test_helper'

module RedmineKit
  module Aws
    module Sqs
      # The actions of the "Jobs" tab as the new UI sends them (kit requests,
      # redmine_kit_ui installed by bin/test's first run): their notices and
      # errors as JSON, with SQS stubbed as the functional tests stub it.
      class KitActionsTest < Redmine::IntegrationTest
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

        test 'resend: the notice, and each record that failed with its error' do
          sent = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          headers = kit_session('admin', 'admin')
          with_queue_url(QUEUE_URL) do
            with_sqs_client(stub_client) do
              post '/admin/aws/jobs/resend.json', params: { ids: [sent.id] }, headers: headers, as: :json
            end
          end
          assert_response :success
          assert_equal({ 'notice' => '1 job(s) resent.', 'errors' => [] }, response.parsed_body)
          assert_not AwsSqsJobFailure.exists?(sent.id)

          kept = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          client = stub_client
          client.stub_responses(:send_message, 'AccessDenied')
          with_queue_url(QUEUE_URL) do
            with_sqs_client(client) do
              post '/admin/aws/jobs/resend.json', params: { ids: [kept.id] }, headers: headers, as: :json
            end
          end
          assert_nil response.parsed_body['notice']
          assert_match(/Aws::SQS::Errors::AccessDenied/, response.parsed_body['errors'].sole)
          assert AwsSqsJobFailure.exists?(kept.id)
        end

        test 'destroy deletes the records; ids that are not a list find nothing' do
          record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
          headers = kit_session('admin', 'admin')
          post '/admin/aws/jobs/destroy.json', params: { ids: record.id.to_s }, headers: headers, as: :json
          assert_response :not_found
          assert AwsSqsJobFailure.exists?(record.id)
          post '/admin/aws/jobs/destroy.json', params: { ids: [record.id] }, headers: headers, as: :json
          assert_response :success
          assert_equal 'Successful deletion.', response.parsed_body['notice']
          assert_not AwsSqsJobFailure.exists?(record.id)
        end

        test 'redrive: a refused call is 422 with the class of the error' do
          client = stub_client
          client.stub_responses(:start_message_move_task, 'AccessDenied')
          with_queue_url(QUEUE_URL) do
            with_sqs_client(client) do
              post '/admin/aws/jobs/redrive.json', headers: kit_session('admin', 'admin'), as: :json
            end
          end
          assert_response 422
          assert_equal ['Could not call the SQS API (Aws::SQS::Errors::AccessDenied). See the log for details.'],
                       response.parsed_body['errors']
        end
      end
    end
  end
end
