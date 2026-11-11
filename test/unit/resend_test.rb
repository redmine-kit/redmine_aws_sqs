# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    # Resending one record from two pages at once sends the job once.
    class ResendTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def test_a_record_is_resent_once
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        other_page = AwsSqsJobFailure.find(record.id)
        client = stub_client
        queue = RedmineAws::SQS::Queue.new(url: QUEUE_URL, client: client)

        assert record.resend!(queue)
        assert_not other_page.resend!(queue)
        assert_equal(1, client.api_requests.count { |r| r[:operation_name] == :send_message })
      end

      def test_a_failed_send_keeps_the_record
        record = record_failure(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        client = stub_client
        client.stub_responses(:send_message, 'QueueDoesNotExist')

        assert_raises(::Aws::SQS::Errors::QueueDoesNotExist) do
          record.resend!(RedmineAws::SQS::Queue.new(url: QUEUE_URL, client: client))
        end
        assert AwsSqsJobFailure.exists?(record.id)
      end
    end
  end
end
