# frozen_string_literal: true

module AwsSqsJobsHelper
  # The queue's counts as the "Jobs" tab shows them (aws_admin/values of
  # redmine_kit_aws, as Administration › Information shows values); "-" for the
  # dead-letter queue when the job queue has none.
  def aws_sqs_jobs_count_rows(counts)
    %i[waiting running delayed dead_letter].map do |name|
      { name: l(:"label_aws_sqs_jobs_#{name}"), value: counts[name].nil? ? '-' : number_with_delimiter(counts[name]) }
    end
  end

  # What the "Jobs" tab shows, as the new UI's JSON (GET admin/aws/jobs.json),
  # formatted as Redmine's page formats it: whether SQS is set, when the
  # counts were read, the counts or the error of reading them, whether the
  # dead-letter queue has messages (the redrive's link), and the failed jobs
  # (the controller's @enabled, @snapshot, @counts, @counts_error, @failures)
  def aws_sqs_jobs_json
    {
      enabled: @enabled,
      updated: @snapshot && format_time(@snapshot.fetched_at),
      counts: @counts && aws_sqs_jobs_count_rows(@counts),
      counts_error: !@counts && @counts_error ? l(:text_aws_sqs_jobs_api_error, error: @counts_error) : nil,
      dead_letter: @counts.present? && @counts[:dead_letter].to_i.positive?,
      failures: @failures.map { |failure| aws_sqs_jobs_failure_json(failure) }
    }
  end

  # A failed job's row: its summary, the class of its error and its times.
  def aws_sqs_jobs_failure_json(failure)
    { id: failure.id, summary: failure.summary, error: failure.error_class, attempts: failure.attempts,
      enqueued_at: failure.enqueued_at ? format_time(failure.enqueued_at) : '-',
      failed_at: format_time(failure.failed_at) }
  end
end
