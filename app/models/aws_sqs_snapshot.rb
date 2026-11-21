# frozen_string_literal: true

# The counts of the job queue and its dead-letter queue that the Jobs tab
# shows (RedmineKit::Aws::Sqs::Queue#counts), as read by the last refresh: the
# tab's Refresh link, or the rake task redmine_kit:aws:sqs:refresh. Only the
# latest is kept. The page never calls SQS.
class AwsSqsSnapshot < ApplicationRecord
  serialize :data, coder: JSON

  def self.latest
    order(fetched_at: :desc, id: :desc).first
  end

  # Reads the counts and keeps them in place of the older snapshots. An
  # error of SQS is kept by its class; its message goes to the log.
  def self.refresh!(queue = RedmineKit::Aws::Sqs::Queue.new)
    snapshot = create!(data: read(queue), fetched_at: Time.current)
    where(fetched_at: ..snapshot.fetched_at).where.not(id: snapshot.id).delete_all
    snapshot
  end

  def self.read(queue)
    { 'queue_url' => queue.url, 'counts' => queue.counts.transform_keys(&:to_s) }
  rescue StandardError => e
    logger&.error "[redmine_kit_aws_sqs] could not read the queue counts: #{e.class}: #{e.message}"
    { 'queue_url' => queue.url, 'error' => e.class.name }
  end

  # The counts (waiting, running, delayed, dead_letter) of the queue at url;
  # nil when the refresh failed, or when it read another queue
  # (REDMINE_SQS_QUEUE_URL changed since).
  def counts(url = RedmineKit::Aws::Sqs::Boot.queue_url)
    data['counts']&.symbolize_keys if current?(url)
  end

  # The class of the error the refresh failed with, on the same terms.
  def error(url = RedmineKit::Aws::Sqs::Boot.queue_url)
    data['error'] if current?(url)
  end

  private

  def current?(url)
    data['queue_url'] == url
  end
end
