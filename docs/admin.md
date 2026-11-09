# Administration page

This is the design of the administration page of Redmine Serverless SQS. Only Redmine administrators can open it (`require_admin`). When [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/admin.html) is installed, the page is a tab of its "Serverless" administration page, and the SQS check joins its connection check. Without it, the page is an item of its own in Redmine's administration menu.

- **No secrets shown:** AWS credentials are not shown. Queue counts are cached for 1 minute.
- **Operations are logged:** Resending and deleting are written to Redmine's log with who did what and when.

## Jobs

| Item | Contents | Source |
| --- | --- | --- |
| Queue counts | Jobs waiting, jobs running, jobs delayed | SQS `GetQueueAttributes` (`ApproximateNumberOfMessages`, etc.) |
| Dead-letter queue count | Number of jobs that used up their retries | Same as above |
| List of failed jobs | Job type (for email, the mail type and recipients; failed email can be listed on its own), error type and message, number of attempts, first and last time | The plugin's table (below) |
| Resend | Put jobs back on SQS one at a time, or the selected ones together | Re-enqueue from the recorded job contents |
| Delete | Remove failures that will not be resent from the list | — |
| Redrive the dead-letter queue | Move jobs in the dead-letter queue back to the original queue | SQS `StartMessageMoveTask` |
| Connection check | Whether SQS is reachable (on Redmine Serverless's "Status and connections" when it is installed) | SQS `GetQueueAttributes` |

- **Recording failures:** When a job fails for the last time (when retries are used up, and on errors that are not retried), the plugin stores the job contents (`job.serialize`) and the error in its table (`serverless_job_failures`). The dead-letter queue is also kept in case writing to the database fails.
- **Resend flow:** Fix the cause first (for example, resume SES sending, or remove an address from the suppression list), then press the resend button. Which email errors are retried is decided by [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/); resending email is described in [Serverless mail.md](https://redmine-kit.github.io/serverless/mail.html#when-sending-fails).

## Permissions

The role of web requests gets permissions to read the queue counts, to resend jobs and to move the dead-letter queue back. The list and an example policy are in [iam.md](iam.md).

## Tests

Functional and system tests for the page ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#administration-pages)).
