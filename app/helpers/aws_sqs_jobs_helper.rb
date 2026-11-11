# frozen_string_literal: true

module AwsSqsJobsHelper
  # The queue's counts as the "Jobs" tab shows them (aws_admin/values of
  # redmine_aws, as Administration › Information shows values); "-" for the
  # dead-letter queue when the job queue has none.
  def aws_sqs_jobs_count_rows(counts)
    %i[waiting running delayed dead_letter].map do |name|
      { name: l(:"label_aws_sqs_jobs_#{name}"), value: counts[name].nil? ? '-' : number_with_delimiter(counts[name]) }
    end
  end
end
