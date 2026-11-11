# Jobs

Administration › AWS › **Jobs** shows Redmine's background jobs on Amazon SQS. **Queue** shows the messages available, in flight and delayed, and the number of jobs in the dead-letter queue. **Failed jobs** lists the jobs that failed for the last time, with their error and attempts.

From the page, an administrator can **Resend** failed jobs, **Delete** their records, or **Start DLQ redrive** to move the jobs in the dead-letter queue back to the job queue. Only the job classes the plugin allows are run.

More: [Redmine AWS SQS: administration page](https://redmine-kit.github.io/redmine_aws_sqs/admin.html).
