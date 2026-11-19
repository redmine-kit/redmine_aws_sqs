# frozen_string_literal: true

module RedmineKit
  module Aws
    module Sqs
      # The work of the rake tasks (lib/tasks/redmine_kit_aws_sqs.rake); each
      # returns the line the task prints and whether it succeeded.
      module Tasks
        # Five digits at most (about 270 years), which keeps the cut-off date
        # well within the database's range.
        MAX_DAYS = 99_999
        DAYS = /\A[1-9][0-9]{0,4}\z/

        module_function

        # DAYS, default AwsSqsJobFailure::KEEP_DAYS. A value that isn't a
        # whole number of days from 1 to MAX_DAYS deletes nothing, and the
        # task aborts with the line, as Redmine's redmine:users:prune does.
        def prune(env)
          days = prune_days(env['DAYS'])
          unless days
            return ["Invalid DAYS #{env['DAYS']} given. The value must be an integer from 1 to #{MAX_DAYS}.", false]
          end

          ["deleted #{AwsSqsJobFailure.prune(days)} record(s) older than #{days} days", true]
        end

        def prune_days(value)
          return AwsSqsJobFailure::KEEP_DAYS if value.nil?

          value.to_i if DAYS.match?(value)
        end
      end
    end
  end
end
