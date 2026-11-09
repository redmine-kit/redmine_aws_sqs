# Setup

What a Redmine needs to use Redmine Serverless SQS: installation, configuration, the AWS resources it expects, IAM permissions and network access. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates. The plugin is in the design stage, so the details below are the design and are checked when the code is written.

## Requirements

- Redmine 7.0 or later.
- AWS's gem `aws-activejob-sqs` (1.2 or later; the plugin's `Gemfile` adds it).
- Something that runs the jobs: on AWS Lambda, a function with an SQS event source and the handler `Aws::ActiveJob::SQS::LambdaHandler.job_handler`; outside Lambda, the gem's poller (`aws_active_job_sqs`).

## Installation

**Getting the plugin:** with Docker, copy it from the plugin's image on ghcr.io, pinned by digest (tags: `main` and `sha-<commit>` for every push to `main`, `v*` for releases):

```dockerfile
COPY --from=ghcr.io/redmine-kit/redmine_serverless_sqs:main@sha256:<digest> /redmine_serverless_sqs plugins/redmine_serverless_sqs/
```

Without Docker, clone the repository (`git clone https://github.com/redmine-kit/redmine_serverless_sqs.git plugins/redmine_serverless_sqs`) or, once releases are published, extract a release archive into `plugins/redmine_serverless_sqs`.

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

The permissions the plugin needs, with an example policy, are in [iam.md](iam.md).

## Network

| Destination | API | In a VPC without internet access |
| --- | --- | --- |
| SQS | `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `GetQueueAttributes`, `StartMessageMoveTask` | Interface endpoint `com.amazonaws.<region>.sqs`, with private DNS so that `sqs.<region>.amazonaws.com` resolves to it |

## Tests

Redmine's standard plugin tests (`bin/rake redmine:plugins:test NAME=redmine_serverless_sqs`). SQS is reproduced with moto; Serverless's image tests run a job from an SQS event and check that a class outside the allowlist is not run ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html)).

## To verify

- Which mechanism in Rails ActiveJob records failures when retries are used up and on errors that are not retried (`after_discard`, etc.)
- How the plugin finds the dead-letter queue
