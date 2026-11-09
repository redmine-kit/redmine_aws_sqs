# Redmine Serverless SQS

Redmine Serverless SQS (`redmine_serverless_sqs`) is a Redmine plugin that runs Redmine's background jobs on Amazon SQS. Jobs go to SQS through AWS's official gem `aws-activejob-sqs`, and the plugin adds what operating them needs: the settings, records of jobs that fail for the last time, and a page to resend them. [Serverless](https://redmine-kit.github.io/serverless/lambda.html#background-jobs) installs it in the Lambda image. It does not modify Redmine's own files. The plugin is in the design stage, and only the documentation exists.

- [Setup](setup.md): requirements, installation, configuration, AWS resources, network, tests
- [IAM permissions](iam.md): permissions, example policy, resource-based policies
- [Administration page](admin.md): jobs

## Features

Each feature has a condition that enables it. Without it, Redmine runs jobs as standard.

| Feature | Contents | Enabled when | Page |
| --- | --- | --- | --- |
| Jobs on SQS | Sets ActiveJob's queue adapter to `aws-activejob-sqs`, maps Redmine's queues (`default`, `mailers`) to the job queue, and allows only Redmine's job classes to run (`ActionMailer::MailDeliveryJob`, `DestroyProjectJob`, `DestroyProjectsJob`, `WebhookJob`) | `REDMINE_JOBS_QUEUE_URL` is set | [setup.md](setup.md#configuration) |
| Job failure records | Jobs that fail for the last time (retries used up, or errors that are not retried) are recorded with their contents and the error, and can be resent | Same as above | [admin.md](admin.md#jobs) |
| Administration page | Queue counts, failed jobs, resending, moving the dead-letter queue back | Administrators | [admin.md](admin.md) |

- **With or without Lambda:** Something has to take jobs from the queue and run them. On AWS Lambda, a function with an SQS event source runs them with the gem's `Aws::ActiveJob::SQS::LambdaHandler` (in Serverless, `redmine-worker`; the handler is set in the image, not in the plugin). Outside Lambda, the gem's poller (`aws_active_job_sqs`) runs as a process of its own, for example on ECS or EC2.
- **Other plugins:** [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/) decides which email errors are retried; email that fails for the last time is recorded here like any other job. When [Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/) is installed, the "Jobs" page is a tab of its "Serverless" page and the SQS check joins its connection check.
- **In Serverless today:** Until this plugin is written, the image sets the queue adapter in `config/additional_environment.rb` and the queues and the allowed job classes in `config/aws_active_job_sqs.yml` ([Serverless lambda.md](https://redmine-kit.github.io/serverless/lambda.html#background-jobs)). The plugin takes these over.
- **Migrations:** A table for the failure records (`serverless_job_failures`). Deployment also runs `redmine:plugins:migrate`.
