# frozen_string_literal: true

require_relative '../test_helper'

module RedmineAws
  module SQS
    class QueueTest < ActiveSupport::TestCase
      include RedmineAws::SQS::TestHelper

      def queue(client)
        RedmineAws::SQS::Queue.new(url: QUEUE_URL, client: client)
      end

      def test_the_dead_letter_queue_comes_from_the_redrive_policy
        q = queue(stub_client)

        assert_equal 3, q.max_receives
        assert_equal DLQ_ARN, q.dead_letter_arn
        assert_equal DLQ_URL, q.dead_letter_url
      end

      def test_counts
        assert_equal({ waiting: 3, running: 1, delayed: 0, dead_letter: 2 }, queue(stub_client).counts)
      end

      def test_counts_without_a_dead_letter_queue
        q = queue(stub_client(dead_letter: false))

        assert_nil q.max_receives
        assert_nil q.counts[:dead_letter]
      end

      def test_counts_are_cached_for_a_minute
        saved = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        client = stub_client
        queue(client).counts
        queue(client).counts

        assert_equal(1, client.api_requests.count { |r| r[:operation_name] == :get_queue_url })
      ensure
        Rails.cache = saved
      end

      def test_redrive_moves_the_dead_letter_queue_back
        client = stub_client
        client.stub_responses(:start_message_move_task, task_handle: 'task-1')

        assert_equal 'task-1', queue(client).redrive
        request = client.api_requests.find { |r| r[:operation_name] == :start_message_move_task }

        assert_equal({ source_arn: DLQ_ARN, destination_arn: QUEUE_ARN }, request[:params])
      end

      def test_redrive_needs_a_dead_letter_queue
        assert_raises(ArgumentError) { queue(stub_client(dead_letter: false)).redrive }
      end

      def test_resend_sends_the_body_as_it_was
        client = stub_client
        body = job_body(DestroyProjectJob.new(1, 1, '127.0.0.1'))
        queue(client).resend(body)
        request = client.api_requests.find { |r| r[:operation_name] == :send_message }

        assert_equal QUEUE_URL, request[:params][:queue_url]
        assert_equal body, request[:params][:message_body]
        assert_equal 'DestroyProjectJob',
                     request[:params][:message_attributes]['aws_sqs_active_job_class'][:string_value]
      end

      def test_resend_refuses_a_job_class_outside_the_allowlist
        client = stub_client
        body = { job_class: 'Kernel', arguments: [] }.to_json

        assert_raises(ArgumentError) { queue(client).resend(body) }
        assert_empty(client.api_requests.select { |r| r[:operation_name] == :send_message })
      end

      def test_check
        assert_equal 'redmine-jobs (Messages available: 3)', queue(stub_client).check
      end
    end
  end
end
