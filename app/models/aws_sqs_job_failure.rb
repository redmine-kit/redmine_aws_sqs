# frozen_string_literal: true

# A job that failed for the last time (docs/admin.md#jobs): its serialized
# contents, to resend it, and the error's class. Contents with a secret in
# the arguments (those RedmineAws::SQS::JobDescription filters in the log,
# such as Mailer#account_information's password) are kept encrypted with a
# key derived from Redmine's secret_key_base, so that the table holds no
# plaintext secret and the job can still be resent. The error's message is in the
# log (RedmineAws::SQS::Failures.log), not here: the page shows the class only.
class AwsSqsJobFailure < ApplicationRecord
  KEEP_DAYS = 90
  MAIL_JOBS = %w[Mailer::DeliveryJob ActionMailer::MailDeliveryJob].freeze

  ENCRYPTED = 'encrypted:'

  validates :job_class, :job_data, :error_class, presence: true

  # body: the message body, which the adapter wrote with job.serialize. The
  # one place where failed jobs are recorded, also by Redmine AWS SES.
  def self.record!(body, error, attempts:, enqueued_at: nil)
    create!(**job_attributes(parse(body)), job_data: stored_body(body.to_s),
                                           error_class: error.class.name.first(255),
                                           attempts: attempts, enqueued_at: enqueued_at, failed_at: Time.current)
  end

  def self.stored_body(body)
    RedmineAws::SQS::JobDescription.from_body(body).secret? ? ENCRYPTED + encryptor.encrypt_and_sign(body) : body
  end

  def self.encryptor
    key = Rails.application.key_generator.generate_key('redmine_aws_sqs job data',
                                                       ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  # The message body as the adapter wrote it.
  def job_body
    return job_data unless job_data.to_s.start_with?(ENCRYPTED)

    self.class.encryptor.decrypt_and_verify(job_data.delete_prefix(ENCRYPTED))
  end

  # The job's class, ID, queue and summary, from its serialized form.
  def self.job_attributes(data)
    { job_class: data['job_class'].to_s.first(255).presence || 'unknown', job_id: data['job_id'].to_s.first(255),
      queue_name: data['queue_name'].to_s.first(255), summary: summarize(data).first(255) }
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
    queue.resend(job_body)
    destroy!
  end
end
