# frozen_string_literal: true

# A job that failed for the last time (docs/admin.md#jobs): its serialized
# contents, to resend it, and the error's class. The error's message is in the
# log (RedmineAws::SQS::Failures.log), not here: the page shows the class only.
class AwsSqsJobFailure < ApplicationRecord
  KEEP_DAYS = 90
  MAIL_JOBS = %w[Mailer::DeliveryJob ActionMailer::MailDeliveryJob].freeze

  validates :job_class, :job_data, :error_class, presence: true

  # body: the message body, which the adapter wrote with job.serialize.
  def self.record!(body, error, attempts:, enqueued_at: nil)
    data = parse(body)
    create!(job_class: data['job_class'].to_s.first(255).presence || 'unknown',
            job_id: data['job_id'].to_s.first(255),
            queue_name: data['queue_name'].to_s.first(255),
            summary: summarize(data).first(255),
            job_data: body.to_s,
            error_class: error.class.name.first(255),
            attempts: attempts,
            enqueued_at: enqueued_at,
            failed_at: Time.current)
  end

  def self.parse(body)
    data = JSON.parse(body.to_s)
    data.is_a?(Hash) ? data : {}
  rescue JSON::ParserError
    {}
  end

  # For mail, the mailer and the mail ("Mailer#issue_add"); the class
  # otherwise.
  def self.summarize(data)
    arguments = Array(data['arguments'])
    if MAIL_JOBS.include?(data['job_class']) && arguments.size >= 2
      "#{arguments[0]}##{arguments[1]}"
    else
      data['job_class'].to_s
    end
  end

  # Deletes the records that failed more than days ago (Serverless
  # docs/security.md#retention-periods); returns how many.
  def self.prune(days = KEEP_DAYS)
    where(failed_at: ...Integer(days).days.ago).delete_all
  end

  def mail?
    MAIL_JOBS.include?(job_class)
  end

  # Puts the job back on the job queue and removes the record.
  def resend!(queue = RedmineAws::SQS::Queue.new)
    queue.resend(job_data)
    destroy!
  end
end
