# Jobs

Administration › AWS › **Jobs** shows Redmine's background jobs on Amazon SQS: the number of messages in the **Job queue** (waiting, running, delayed) and **In the dead-letter queue**, and the **Failed jobs** with their error and attempts.

From the page, an administrator can send a failed job again, delete its record, or move the messages of the dead-letter queue back to the job queue. Only the job classes the plugin allows are run.

More: [Redmine AWS SQS: administration page](https://redmine-kit.github.io/redmine_aws_sqs/admin.html).
