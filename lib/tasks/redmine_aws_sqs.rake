# frozen_string_literal: true

namespace :redmine_aws_sqs do
  desc 'Deletes the records of failed jobs older than the given days: prune_records[90] (default 90)'
  task :prune_records, [:days] => :environment do |_task, args|
    days = args[:days].presence || AwsSqsJobFailure::KEEP_DAYS
    puts "deleted #{AwsSqsJobFailure.prune(days)} record(s) older than #{days} days"
  end
end
