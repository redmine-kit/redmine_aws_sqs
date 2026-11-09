# frozen_string_literal: true

require_relative '../test_helper'

module RedmineServerlessSqs
  # The handlers the plugin gives the gem's poller (outside Lambda).
  class PollerHandlersTest < ActiveSupport::TestCase
    include RedmineServerlessSqs::TestHelper

    def sqs_message(body, receives:)
      data = Aws::SQS::Types::Message.new(body: body, receipt_handle: 'handle', message_id: '1', attributes: {
                                            'ApproximateReceiveCount' => receives.to_s,
                                            'SentTimestamp' => (Time.now.to_f * 1000).to_i.to_s
                                          })
      Aws::SQS::Message.new(queue_url: QUEUE_URL, receipt_handle: 'handle', data: data,
                            client: Aws::SQS::Client.new(stub_responses: true))
    end

    def body
      job_body(DestroyProjectJob.new(1, 1, '127.0.0.1'))
    end

    def call_error_handler(receives)
      with_queue_url(QUEUE_URL) do
        with_sqs_client(stub_client) do
          Aws::ActiveJob::SQS.config.poller_error_handler.call(RuntimeError.new('boom'),
                                                               sqs_message(body, receives: receives))
        end
      end
    end

    def test_handlers_are_set
      assert_not_nil Aws::ActiveJob::SQS.config.poller_error_handler
      assert_not_nil Aws::ActiveJob::SQS.config.permanent_failure_handler
    end

    def test_a_failure_before_the_last_receive_is_not_recorded
      assert_no_difference('ServerlessJobFailure.count') { call_error_handler(2) }
    end

    def test_a_failure_on_the_last_receive_is_recorded
      assert_difference('ServerlessJobFailure.count', 1) { call_error_handler(3) }
      assert_equal 'DestroyProjectJob', ServerlessJobFailure.last.job_class
    end

    def test_a_message_that_can_never_run_is_recorded
      error = Aws::ActiveJob::SQS::InvalidJobClassError.new('Kernel is not in the configured job_class_allowlist')
      message = sqs_message('{"job_class":"Kernel"}', receives: 1)
      assert_difference('ServerlessJobFailure.count', 1) do
        Aws::ActiveJob::SQS.config.permanent_failure_handler.call(error, message)
      end
    end
  end
end
