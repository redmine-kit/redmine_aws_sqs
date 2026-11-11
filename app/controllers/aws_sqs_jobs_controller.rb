# frozen_string_literal: true

# The "Jobs" tab (docs/admin.md#jobs): queue counts, failed jobs, resending,
# deleting and moving the dead-letter queue back. Operations are logged.
class AwsSqsJobsController < ApplicationController
  include RedmineAws::AdminTab

  before_action :find_failures, only: %i[resend destroy]

  def index
    @enabled = RedmineAws::SQS.enabled?
    @counts, @counts_error = queue_counts if @enabled
    scope = AwsSqsJobFailure.order(failed_at: :desc)
    scope = scope.where(job_class: AwsSqsJobFailure::MAIL_JOBS) if params[:mail] == '1'
    @failures = scope.limit(100).to_a
  end

  def resend
    sent = @failures.count do |failure|
      failure.resend!
      true
    rescue StandardError => e
      # The summary comes from the message body, and Redmine shows flash
      # messages as HTML (render_flash_messages).
      flash[:error] = ERB::Util.h("#{failure.summary}: #{api_error(e, job: failure.job_data)}")
      false
    end
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

  # A short message for the page (the AWS error code, or the class), with the
  # details in the log. job: the message body of a job it concerns,
  # described with its arguments filtered (RedmineAws::SQS::JobDescription).
  def api_error(error, job: nil)
    about = "#{RedmineAws::SQS::JobDescription.from_body(job)}: " if job
    logger&.error "[redmine_aws_sqs] #{about}#{error.class}: #{error.message}"
    l(:text_aws_sqs_jobs_api_error,
      error: error.respond_to?(:code) && error.code.present? ? error.code : error.class.name)
  end

  def audit(what)
    logger&.info "[redmine_aws_sqs] #{User.current.login} #{what}"
  end
end
