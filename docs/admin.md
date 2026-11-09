# Administration page

This is the administration page of Redmine Serverless SQS. Only Redmine administrators can open it (`require_admin`). The page is the "Jobs" tab under the "Serverless" item of Redmine's administration menu, which all the Redmine Serverless plugins share, whether or not [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html#the-serverless-menu) is installed. When Redmine Serverless is installed, the SQS check also joins its connection check.

- **No secrets shown:** AWS credentials and the message bodies of failed jobs are not shown. Queue counts are cached for 1 minute.
- **Operations are logged:** Resending, deleting and moving the dead-letter queue back are written to Redmine's log with who did what (`[redmine_serverless_sqs] <login> resent 1 of 1 job(s)`).

## Jobs

| Item | Contents | Source |
| --- | --- | --- |
| Queue counts | Jobs waiting, jobs running, jobs delayed | SQS `GetQueueAttributes` (`ApproximateNumberOfMessages`, etc.) |
| Dead-letter queue count | Number of jobs in the dead-letter queue | `GetQueueAttributes` of the dead-letter queue, found from the job queue's redrive policy |
| List of failed jobs | The job (for email, the mailer and the mail, such as `Mailer#issue_add`; failed email can be listed on its own), error class and message, number of receives, when it was queued and when it failed. The newest 100 | The plugin's table (below) |
| Resend | Puts the selected jobs back on the job queue, and removes their records | `SendMessage` with the recorded message |
| Delete | Removes the selected records | — |
| Move the dead-letter queue back | Moves the jobs in the dead-letter queue back to the job queue. Shown when the dead-letter queue has jobs | SQS `StartMessageMoveTask` |
| Connection check | Whether SQS is reachable (on Redmine Serverless's "Status and connections" when it is installed) | SQS `GetQueueAttributes` |

- **Recording failures:** A job that raises is retried by SQS. The plugin records it on the receive after which SQS moves the message to the dead-letter queue (the `ApproximateReceiveCount` of the message reaches the `maxReceiveCount` of the job queue's redrive policy). It stores the message body (`job.serialize`), the error and the number of receives in its table (`serverless_job_failures`), and the message still moves to the dead-letter queue, in case writing to the database fails. A message that can never run (not JSON, or a job class outside the allowed ones) is recorded at once and deleted, without retries. Without a redrive policy, SQS keeps a failing message until its retention period ends, and nothing is recorded.
- **Where it is recorded:** On Lambda, the plugin wraps the gem's handler (`Aws::ActiveJob::SQS::LambdaHandler.job_handler`, by `prepend`). With the gem's poller, it sets the gem's `poller_error_handler` and `permanent_failure_handler`, unless the application set its own.
- **Resending:** The recorded message body is sent to the job queue as it was, with the message attributes the adapter writes. Only a job of an allowed class is sent; the job runs again with the same job ID. The record and the dead-letter queue are separate: a resent job is usually still in the dead-letter queue too, so resend it from one place only (moving the dead-letter queue back as well would run it twice).
- **Resend flow:** Fix the cause first (for example, resume SES sending, or remove an address from the suppression list), then resend. Which email errors are retried is decided by [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/); resending email is described in [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#when-sending-fails).
- **Recipients:** The list does not show the recipients of failed email. A mail job holds the user as a reference to the record, not the address.
- **Without the job queue:** Without `REDMINE_JOBS_QUEUE_URL`, the page says that Redmine runs jobs as standard, shows the records that are left, and cannot resend.

## Permissions

The role of web requests gets permissions to read the queue counts, to resend jobs and to move the dead-letter queue back. The list and an example policy are in [iam.md](iam.md).

## Tests

Functional tests for the page, on SDK response stubs ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
