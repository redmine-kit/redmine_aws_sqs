# IAM permissions

The plugin's own calls to AWS, by the role of the process. Lambda's own permissions (logs, running in a VPC) are not included; [Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html) has the full roles.

## Permissions

| Action | Resource | Why |
| --- | --- | --- |
| `sqs:SendMessage` | The job queue | Every process that enqueues jobs (web requests, jobs, rake), and resending from the "Jobs" page |
| `sqs:ReceiveMessage`<br>`sqs:DeleteMessage`<br>`sqs:ChangeMessageVisibility`<br>`sqs:GetQueueAttributes` | The job queue | What runs the jobs: the Lambda event source mapping (with the function's role) or the poller. The gem deletes messages that succeeded. `GetQueueAttributes` also reads the redrive policy when a job fails, to know whether it was the last receive |
| `sqs:GetQueueAttributes` | The job queue and the dead-letter queue | Queue counts on the "Jobs" page, and the SQS connection test on the "Status" tab |
| `sqs:GetQueueUrl` | The dead-letter queue | The URL of the dead-letter queue, from the ARN in the redrive policy, for its count |
| `sqs:StartMessageMoveTask`<br>`sqs:ReceiveMessage`<br>`sqs:DeleteMessage` | The dead-letter queue | The DLQ redrive to the job queue from the "Jobs" page. The caller also needs `sqs:SendMessage` on the job queue (above) |

Sending to the job queue (`sqs:SendMessage`) is as strong as running code in the process that runs the jobs, because the jobs trust their messages: a mail job calls the class and the method that its message names (`ActionMailer::MailDeliveryJob`), and Redmine's jobs destroy the project or call the webhook with the IDs in the message. The allowed job classes limit the classes, not their arguments. Give `sqs:SendMessage` on the job queue only to Redmine's own roles.

The permissions for moving messages back are AWS's minimum for starting a dead-letter queue redrive: `sqs:StartMessageMoveTask`, `sqs:ReceiveMessage`, `sqs:DeleteMessage` and `sqs:GetQueueAttributes` on the dead-letter queue, and `sqs:SendMessage` on the destination ([Amazon SQS Developer Guide](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html), checked on 2026-11-10). A customer managed KMS key would also need `kms:Decrypt` and `kms:GenerateDataKey`; the queues here use SQS-managed keys.

## Example policy

For the role of web requests (enqueuing, the "Jobs" page):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnqueueAndJobsPage",
      "Effect": "Allow",
      "Action": ["sqs:SendMessage", "sqs:GetQueueAttributes"],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs"
    },
    {
      "Sid": "DeadLetterQueue",
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:StartMessageMoveTask",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage"
      ],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs-dlq"
    }
  ]
}
```

For the role that runs jobs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RunJobs",
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage"
      ],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs"
    }
  ]
}
```

## Resource-based policies

None. The queues use SQS-managed encryption keys, so no key policy is needed. Don't add a queue policy that lets other principals send to the job queue ([Permissions](#permissions)).

## Not checked yet

- The policies above on real queues (the tests use AWS Emulator, which does not evaluate IAM policies).
