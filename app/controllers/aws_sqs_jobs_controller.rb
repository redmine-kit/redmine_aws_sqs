# frozen_string_literal: true

# The "Jobs" tab (docs/admin.md#jobs): queue counts, failed jobs, resending,
# deleting and moving the dead-letter queue back. Operations are logged.
class AwsSqsJobsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin
  before_action :find_failures, only: %i[resend destroy]

  def index
    @enabled = RedmineAwsSqs.enabled?
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
      flash[:error] = "#{failure.summary}: #{api_error(e)}"
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
    task = RedmineAwsSqs::Queue.new.redrive
    audit("started moving the dead-letter queue back (#{task})")
    flash[:notice] = l(:notice_aws_sqs_jobs_redrive_started)
  rescue StandardError => e
    flash[:error] = api_error(e)
  ensure
    redirect_to action: 'index'
  end

  private

  def find_failures
    @failures = AwsSqsJobFailure.where(id: Array(params[:ids]).map(&:to_i)).to_a
    render_404 if @failures.empty?
  end

  def queue_counts
    [RedmineAwsSqs::Queue.new.counts, nil]
  rescue StandardError => e
    [nil, api_error(e)]
  end

  # A short message for the page (the AWS error code, or the class), with the
  # details in the log.
  def api_error(error)
    logger&.error "[redmine_aws_sqs] #{error.class}: #{error.message}"
    l(:text_aws_sqs_jobs_api_error,
      error: error.respond_to?(:code) && error.code.present? ? error.code : error.class.name)
  end

  def audit(what)
    logger&.info "[redmine_aws_sqs] #{User.current.login} #{what}"
  end
end
