# frozen_string_literal: true

# The "Jobs" tab (docs/admin.md#jobs): queue counts, failed jobs, resending,
# deleting and moving the dead-letter queue back. Operations are logged.
class ServerlessJobsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :serverless

  before_action :require_admin
  before_action :find_failures, only: %i[resend destroy]

  def index
    @enabled = RedmineServerlessSqs.enabled?
    @counts, @counts_error = queue_counts if @enabled
    scope = ServerlessJobFailure.order(failed_at: :desc)
    scope = scope.where(job_class: ServerlessJobFailure::MAIL_JOBS) if params[:mail] == '1'
    @failures = scope.limit(100).to_a
  end

  def resend
    sent = @failures.count do |failure|
      failure.resend!
      true
    rescue StandardError => e
      flash[:error] = "#{failure.summary}: #{e.class}: #{e.message}"
      false
    end
    audit("resent #{sent} of #{@failures.size} job(s)")
    flash[:notice] = l(:notice_serverless_jobs_resent, count: sent) if sent.positive?
    redirect_to action: 'index'
  end

  def destroy
    @failures.each(&:destroy!)
    audit("deleted #{@failures.size} failure record(s)")
    flash[:notice] = l(:notice_successful_delete)
    redirect_to action: 'index'
  end

  def redrive
    task = RedmineServerlessSqs::Queue.new.redrive
    audit("started moving the dead-letter queue back (#{task})")
    flash[:notice] = l(:notice_serverless_jobs_redrive_started)
  rescue StandardError => e
    flash[:error] = "#{e.class}: #{e.message}"
  ensure
    redirect_to action: 'index'
  end

  private

  def find_failures
    @failures = ServerlessJobFailure.where(id: Array(params[:ids]).map(&:to_i)).to_a
    render_404 if @failures.empty?
  end

  def queue_counts
    [RedmineServerlessSqs::Queue.new.counts, nil]
  rescue StandardError => e
    [nil, "#{e.class}: #{e.message}"]
  end

  def audit(what)
    logger&.info "[redmine_serverless_sqs] #{User.current.login} #{what}"
  end
end
