# Setup

What a Redmine needs to use Redmine Serverless SQS: installation, configuration, the AWS resources it expects, IAM permissions and network access. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in the design stage, so the details below are the design and are checked when the code is written.

## Requirements

- Redmine 7.0 or later.
- AWS's gem `aws-activejob-sqs` (1.2 or later; the plugin's `Gemfile` adds it).
- Something that runs the jobs: on AWS Lambda, a function with an SQS event source and the handler `Aws::ActiveJob::SQS::LambdaHandler.job_handler`; outside Lambda, the gem's poller (`aws_active_job_sqs`).

## Installation

1. Put the plugin in `plugins/redmine_serverless_sqs` and run `bundle install` (the plugin's `Gemfile` is loaded by Redmine's).
2. Run `bin/rake redmine:plugins:migrate`. It creates the table of failure records (`serverless_job_failures`).

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | Environment variable of every process (web, jobs, rake) | The URL of the job queue. Turns the plugin on |
| Queues | Set by the plugin | Redmine's queues `default` and `mailers` both go to the job queue |
| Allowed job classes | Set by the plugin | `ActionMailer::MailDeliveryJob`, `DestroyProjectJob`, `DestroyProjectsJob`, `WebhookJob`. A message for another class is not run (the gem's `job_class_allowlist`) |

- **Message deletion:** The gem deletes a message after its job succeeds. On Lambda it builds the queue URL from the event's ARN (`https://sqs.<region>.amazonaws.com/...`), so the function must reach that address (checked in Serverless's image tests on 2026-11-09).
- **The dead-letter queue:** How the plugin finds the dead-letter queue for the "Jobs" page (a setting of its own, or the job queue's redrive policy) is decided when the code is written (not decided yet).

## AWS resources

| Resource | Settings |
| --- | --- |
| SQS job queue | A standard queue. Visibility timeout longer than the time a job may take (on Lambda, six times the function's timeout). A redrive policy to the dead-letter queue after 3 receives. Server-side encryption with SQS-managed keys |
| SQS dead-letter queue | Receives the jobs that failed 3 times. The "Jobs" page moves them back with `StartMessageMoveTask` |
| What runs the jobs | On Lambda: a function with an SQS event source mapping on the job queue (batch size 1). Outside Lambda: a process running the gem's poller |

## IAM permissions

The plugin's own calls to AWS, by the role of the process. Lambda's own permissions (logs, running in a VPC) are not included; [Serverless iam.md](https://redmine-kit.github.io/serverless/iam.html) has the full roles.

| Action | Resource | Why |
| --- | --- | --- |
| `sqs:SendMessage` | The job queue | Every process that enqueues jobs (web requests, jobs, rake), and resending from the "Jobs" page |
| `sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:ChangeMessageVisibility`, `sqs:GetQueueAttributes` | The job queue | What runs the jobs: the Lambda event source mapping (with the function's role) or the poller. The gem deletes messages that succeeded |
| `sqs:GetQueueAttributes` | The job queue and the dead-letter queue | Queue counts on the "Jobs" page, and the SQS check on "Status and connections" |
| `sqs:StartMessageMoveTask`, `sqs:ListMessageMoveTasks` | The dead-letter queue | Moving the dead-letter queue back to the job queue from the "Jobs" page |

### Example policy

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

### Resource-based policies

None. The queues use SQS-managed encryption keys, so no key policy is needed.

### Not checked yet

- Whether the caller of `StartMessageMoveTask` also needs `sqs:ReceiveMessage` and `sqs:DeleteMessage` on the dead-letter queue and `sqs:SendMessage` on the job queue.

## Network

| Destination | API | In a VPC without internet access |
| --- | --- | --- |
| SQS | `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `GetQueueAttributes`, `StartMessageMoveTask` | Interface endpoint `com.amazonaws.<region>.sqs`, with private DNS so that `sqs.<region>.amazonaws.com` resolves to it |

## Tests

Redmine's standard plugin tests (`bin/rake redmine:plugins:test NAME=redmine_serverless_sqs`). SQS is reproduced with moto; Serverless's image tests run a job from an SQS event and check that a class outside the allowlist is not run ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html)).

## To verify

- Which mechanism in Rails ActiveJob records failures when retries are used up and on errors that are not retried (`after_discard`, etc.)
- How the plugin finds the dead-letter queue
