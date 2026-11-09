# IAM permissions

The plugin's own calls to AWS, by the role of the process. Lambda's own permissions (logs, running in a VPC) are not included; [Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html) has the full roles.

## Permissions

| Action | Resource | Why |
| --- | --- | --- |
| `sqs:SendMessage` | The job queue | Every process that enqueues jobs (web requests, jobs, rake), and resending from the "Jobs" page |
| `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:ChangeMessageVisibility`, `sqs:GetQueueAttributes` | The job queue | What runs the jobs: the Lambda event source mapping (with the function's role) or the poller. The gem deletes messages that succeeded |
| `sqs:GetQueueAttributes` | The job queue and the dead-letter queue | Queue counts on the "Jobs" page, and the SQS check on "Status and connections" |
| `sqs:StartMessageMoveTask`, `sqs:ListMessageMoveTasks` | The dead-letter queue | Moving the dead-letter queue back to the job queue from the "Jobs" page |

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
      "Resource": [
        "arn:aws:sqs:<region>:<account>:<instance>-jobs",
        "arn:aws:sqs:<region>:<account>:<instance>-jobs-dlq"
      ]
    },
    {
      "Sid": "Redrive",
      "Effect": "Allow",
      "Action": ["sqs:StartMessageMoveTask", "sqs:ListMessageMoveTasks"],
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

None. The queues use SQS-managed encryption keys, so no key policy is needed.

## Not checked yet

- Whether the caller of `StartMessageMoveTask` also needs `sqs:ReceiveMessage` and `sqs:DeleteMessage` on the dead-letter queue and `sqs:SendMessage` on the job queue.
