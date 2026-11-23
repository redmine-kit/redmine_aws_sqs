# frozen_string_literal: true

# The "Jobs" tab (docs/admin.md#jobs): queue counts (as the last refresh
# stored them, AwsSqsSnapshot; the page itself never calls SQS), failed jobs,
# resending, deleting and moving the dead-letter queue back. Operations are
# logged. Redmine's page (HTML, with redirects and flash messages), and the
# same data and actions as JSON for the new UI's tab (AwsSqsJobs of
# frontend/; AwsSqsJobsHelper#aws_sqs_jobs_json).
class AwsSqsJobsController < ApplicationController
  include RedmineKit::Aws::AdminTab

  helper :aws_sqs_jobs

  before_action :find_failures, only: %i[resend destroy]

  def index
    load_page
    respond_to do |format|
      format.html
      format.json { render json: view_context.aws_sqs_jobs_json }
    end
  end

  def resend
    errors = []
    sent = @failures.count { |failure| resend_one(failure, errors) }
    # Every failed record, each in the form of the API error.
    audit("resent #{sent} of #{@failures.size} job(s)")
    resent(sent.positive? ? l(:notice_aws_sqs_jobs_resent, count: sent) : nil, errors)
  end

  def destroy
    @failures.each(&:destroy!)
    audit("deleted #{@failures.size} failure record(s)")
    done(l(:notice_successful_delete))
  end

  # Reads the queue counts from SQS again; an error is stored with them and
  # shown by its class.
  def refresh
    if RedmineKit::Aws::Sqs.enabled?
      AwsSqsSnapshot.refresh!
      audit('refreshed the queue counts')
    end
    done(nil)
  end

  def redrive
    task = RedmineKit::Aws::Sqs::Queue.new.redrive
    audit("started moving the dead-letter queue back (#{task})")
    done(l(:notice_aws_sqs_jobs_redrive_started))
  rescue StandardError => e
    failed(api_error(e))
  end

  private

  # What the tab shows: the counts the last refresh stored, and the last 100
  # failed jobs (the mail jobs only with mail=1).
  def load_page
    @enabled = RedmineKit::Aws::Sqs.enabled?
    @snapshot = AwsSqsSnapshot.latest if @enabled
    @counts = @snapshot&.counts
    @counts_error = @snapshot&.error
    scope = AwsSqsJobFailure.order(failed_at: :desc)
    scope = scope.where(job_class: AwsSqsJobFailure::MAIL_JOBS) if params[:mail] == '1'
    @failures = scope.limit(100).to_a
  end

  # A resend's notice and each record's error: back to the page with them
  # (Redmine shows flash messages as HTML: render_flash_messages), or as JSON.
  def resent(notice, errors)
    respond_to do |format|
      format.html do
        flash[:error] = ERB::Util.h(errors.join(' ')) if errors.any?
        flash[:notice] = notice if notice
        redirect_to action: 'index'
      end
      format.json { render json: { notice: notice, errors: errors } }
    end
  end

  # An action that worked: back to the page with its notice, or the notice as
  # JSON.
  def done(notice)
    respond_to do |format|
      format.html do
        flash[:notice] = notice if notice
        redirect_to action: 'index'
      end
      format.json { render json: { notice: notice, errors: [] } }
    end
  end

  # An action that failed: back to the page with the error, or the error as
  # JSON (422).
  def failed(error)
    respond_to do |format|
      format.html do
        flash[:error] = ERB::Util.h(error)
        redirect_to action: 'index'
      end
      format.json { render json: { errors: [error] }, status: :unprocessable_content }
    end
  end

  # Any error of one record (a body that cannot be decrypted any more, an
  # SQS error) is that record's: it is added to errors, with the summary,
  # which comes from the message body, and the others are still sent.
  def resend_one(failure, errors)
    failure.resend!
  rescue ActiveSupport::MessageEncryptor::InvalidMessage => e
    # Encrypted under another secret_key_base: SQS was not called.
    logger&.error "[redmine_kit_aws_sqs] #{failure.log_name}: #{e.class}: the job's data cannot be decrypted"
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

  # A short message for the page with the error's class, as redmine_kit_aws's
  # connection checks show it; the message, which comes from the service and
  # may name accounts or resources, goes to the log.
  # about: the job it concerns (AwsSqsJobFailure#log_name, from fields that
  # cannot fail). A parser error's message quotes the body, which is not
  # trusted: the class only.
  def api_error(error, about: nil)
    message = ": #{error.message}" unless error.is_a?(JSON::ParserError)
    logger&.error "[redmine_kit_aws_sqs] #{"#{about}: " if about}#{error.class}#{message}"
    l(:text_aws_sqs_jobs_api_error, error: error.class.name)
  end

  def audit(what)
    logger&.info "[redmine_kit_aws_sqs] #{User.current.login} #{what}"
  end
end
