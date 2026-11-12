# Redmine AWS SQS

Redmine AWS SQS (`redmine_aws_sqs`) is a Redmine plugin that runs Redmine's background jobs on Amazon SQS. Jobs go to SQS through AWS's official gem `aws-activejob-sqs`, and the plugin adds what operating them needs: the settings, records of jobs that fail for the last time, and a page to resend them. [Serverless](https://redmine-kit.github.io/serverless/lambda.html#background-jobs) installs it in the Lambda image. It does not modify Redmine's own files. The plugin is in early development.

- [Setup](setup.md): requirements, installation, configuration, AWS resources, network, tests
- [IAM permissions](iam.md): permissions, example policy, resource-based policies
- [Administration page](admin.md): jobs

## Features

Each feature has a condition that enables it. Without it, Redmine runs jobs as standard.

| Feature | Contents | Enabled when | Page |
| --- | --- | --- | --- |
| Jobs on SQS | Sets ActiveJob's queue adapter to `aws-activejob-sqs`, maps Redmine's queues (`default`, `mailers`) to the job queue, and allows only Redmine's job classes and those of the other Redmine AWS plugins to run (`Mailer::DeliveryJob`, `DestroyProjectJob`, `DestroyProjectsJob`, `WebhookJob`, `AwsS3ReconcileJob`, `AwsSesReimportMailJob`) | `REDMINE_JOBS_QUEUE_URL` is set | [setup.md](setup.md#configuration) |
| Job failure records | Jobs that fail for the last time (on the last receive before the dead-letter queue, or messages that can never run) are recorded with their contents and the error, and can be resent | Same as above | [admin.md](admin.md#jobs) |
| Administration page | The "Jobs" tab under the "AWS" menu of [Redmine AWS](https://redmine-kit.github.io/redmine_aws/admin.html#the-aws-menu): queue counts, failed jobs, resending, the DLQ redrive | Administrators | [admin.md](admin.md) |

## Running the jobs

Something has to take the jobs from the queue and run them, and the plugin records failures either way:

- **On AWS Lambda,** a function with an SQS event source runs them with the gem's `Aws::ActiveJob::SQS::LambdaHandler.job_handler`. In Serverless this is `redmine-worker`, and the handler is set in the image, not in the plugin.
- **Outside Lambda,** the gem's poller (`aws_active_job_sqs`) runs as a process of its own, for example on ECS or EC2.

## Other plugins

A plugin with job classes of its own adds them to the allowed classes by calling `RedmineAws::SQS::Boot.allow_job('ClassName')` in its `init.rb`.

[Redmine AWS SES](https://redmine-kit.github.io/redmine_aws_ses/) decides which email errors are retried. Email that fails for the last time is recorded here like any other job. The "Jobs" page is a tab of the "AWS" page of [Redmine AWS](https://redmine-kit.github.io/redmine_aws/), which this plugin requires, and the SQS check joins the connection test on its "Status" tab.

## In Serverless

The plugin sets the queue adapter, the queues and the allowed job classes, so the image needs neither `config/additional_environment.rb` nor `config/aws_active_job_sqs.yml` for them ([Serverless lambda.md](https://redmine-kit.github.io/serverless/lambda.html#background-jobs)).

## Code layout

The code is under the `RedmineAws` namespace of Redmine AWS, as `RedmineAws::SQS`. `boot/redmine_aws_sqs.rb` (`RedmineAws::SQS::Boot`) sets the queue adapter and the gem's settings. Because the plugin is also a gem, Bundler loads this file before Rails initializes ([setup.md](setup.md#installation)). The rest is in `lib/redmine_aws/sqs.rb`, `lib/redmine_aws/sqs/`, `app/` and `db/`, which Redmine loads, and `init.rb` turns it on. The "AWS" administration menu, its tabs and the connection test come from [Redmine AWS](https://redmine-kit.github.io/redmine_aws/) (`redmine_aws`), which the plugin requires.

## Database tables

The plugin adds a table for the failure records (`aws_sqs_job_failures`). Deployment also runs `redmine:plugins:migrate`.

## Sponsors

<Sponsors ids="keyselect"><a href="https://www.keyselect.co.jp/">KEY SELECT</a></Sponsors>

## License

Redmine AWS SQS is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](../LICENSE). An unofficial Redmine plugin.
