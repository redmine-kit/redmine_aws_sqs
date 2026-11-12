# frozen_string_literal: true

# The "Jobs" tab (docs/admin.md#jobs): queue counts, failed jobs, resending,
# deleting and moving the dead-letter queue back. Operations are logged.
class AwsSqsJobsController < ApplicationController
  include RedmineAws::AdminTab

  helper :aws_sqs_jobs

  before_action :find_failures, only: %i[resend destroy]

  def index
    @enabled = RedmineAws::SQS.enabled?
    @counts, @counts_error = queue_counts if @enabled
    scope = AwsSqsJobFailure.order(failed_at: :desc)
    scope = scope.where(job_class: AwsSqsJobFailure::MAIL_JOBS) if params[:mail] == '1'
    @failures = scope.limit(100).to_a
  end

  def resend
    errors = []
    sent = @failures.count { |failure| resend_one(failure, errors) }
    # Every failed record, each in the form of the API error; Redmine shows
    # flash messages as HTML (render_flash_messages).
    flash[:error] = ERB::Util.h(errors.join(' ')) if errors.any?
    audit("resent #{sent} of #{@failures.size} job(s)")
    flash[:notice] = l(:notice_aws_sqs_jobs_resent, count: sent) if sent.positive?
    redirect_to action: 'index'
  end

  def destroy
    @failures.each(&:destroy!)
    audit("deleted #{@failures.size} failure record(s)")
    flash[:notice] = l(:notice_successful_delete)
    redirect_to action: 'index'
  end

  def redrive
    task = RedmineAws::SQS::Queue.new.redrive
    audit("started moving the dead-letter queue back (#{task})")
    flash[:notice] = l(:notice_aws_sqs_jobs_redrive_started)
  rescue StandardError => e
    flash[:error] = ERB::Util.h(api_error(e))
  ensure
    redirect_to action: 'index'
  end

  private

  # Any error of one record (a body that cannot be decrypted any more, an
  # SQS error) is that record's: it is added to errors, with the summary,
  # which comes from the message body, and the others are still sent.
  def resend_one(failure, errors)
    failure.resend!
  rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
    # Encrypted under another secret_key_base: SQS was not called.
    logger&.error "[redmine_aws_sqs] #{failure.log_name}: #{e.class}: the job's data cannot be decrypted"
    errors << "#{failure.summary}: #{l(:text_aws_sqs_jobs_undecryptable, error: e.class.name)}"
    false
  rescue StandardError => e
    errors << "#{failure.summary}: #{api_error(e, about: failure.log_name)}"
    false
  end

  # The records of the ids[] of the form; anything else in ids (a single
  # value, a hash) finds nothing.
  def find_failures
    ids = params.permit(ids: [])[:ids]
    @failures = ids.blank? ? [] : AwsSqsJobFailure.where(id: ids).to_a
    render_404 if @failures.empty?
  end

  def queue_counts
    [RedmineAws::SQS::Queue.new.counts, nil]
  rescue StandardError => e
    [nil, api_error(e)]
  end

  # A short message for the page with the error's class, as redmine_aws's
  # connection checks show it; the message, which comes from the service and
  # may name accounts or resources, goes to the log.
  # about: the job it concerns (AwsSqsJobFailure#log_name, from fields that
  # cannot fail). A parser error's message quotes the body, which is not
  # trusted: the class only.
  def api_error(error, about: nil)
    message = ": #{error.message}" unless error.is_a?(JSON::ParserError)
    logger&.error "[redmine_aws_sqs] #{"#{about}: " if about}#{error.class}#{message}"
    l(:text_aws_sqs_jobs_api_error, error: error.class.name)
  end

  def audit(what)
    logger&.info "[redmine_aws_sqs] #{User.current.login} #{what}"
  end
end
