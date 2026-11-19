# frozen_string_literal: true

# The tasks' work is in RedmineKit::Aws::Sqs::Tasks.
namespace :redmine_kit do
  namespace :aws do
    namespace :sqs do
      desc 'Deletes the records of jobs that failed more than a number of days ago. ' \
           'Use DAYS to set the number of days (default 90).'
      task prune: :environment do
        line, ok = RedmineKit::Aws::Sqs::Tasks.prune(ENV)
        ok ? puts(line) : abort(line)
      end
    end
  end
end
