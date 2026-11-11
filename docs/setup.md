# Setup

What a Redmine needs to use Redmine AWS SQS: installation, configuration, the AWS resources it expects, IAM permissions and network access. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates.

## Requirements

- Redmine 7.0 or later.
- AWS's gem `aws-activejob-sqs` 1.2 or later (a dependency of the gem; with a checkout, the plugin's `Gemfile` adds it).
- Something that runs the jobs: on AWS Lambda, a function with an SQS event source and the handler `Aws::ActiveJob::SQS::LambdaHandler.job_handler`; outside Lambda, the gem's poller (`aws_active_job_sqs`).

## Installation

1. Get the plugin into `plugins/redmine_aws_sqs` of Redmine 7.0: the gem below, or a checkout of this repository.
2. Add the plugin to `Gemfile.local` as a gem, and install it:

   ```sh
   bundle install
   ```

   Bundler then loads `boot/redmine_aws_sqs.rb` before Rails initializes: the queue adapter must be set by then, and Redmine's own loading of plugins (`init.rb`) comes too late for it. With a checkout, add it by path:

   ```ruby
   # Redmine's Gemfile.local
   gem 'redmine_aws_sqs', path: 'plugins/redmine_aws_sqs'
   ```

3. Run the plugin's migrations:

   ```sh
   bin/rake redmine:plugins:migrate
   ```

   They create the table of failure records (`aws_sqs_job_failures`).
4. Remove settings of `aws-activejob-sqs` made elsewhere, if any: a queue adapter set in `config/additional_environment.rb`, and `config/aws_active_job_sqs.yml`. The plugin sets both.

### Gem

Each version tag (`v*`) publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`; `.github/workflows/gem.yml`). The gem holds the run-time files (`init.rb`, `boot/`, `lib/`, `app/`, `config/`, `db/`, `LICENSE`); the plugin's `Gemfile` is not in it. Redmine loads plugins only from `plugins/`, so the installed gem is linked there:

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_aws_sqs'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <user>:<token>   # or BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_aws_sqs)" plugins/redmine_aws_sqs
```

Installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. A workflow of another repository reads it with its `GITHUB_TOKEN` (`packages: read`) once the package's settings ("Manage Actions access") give that repository Read.

## Configuration

| Key | Description | Parameter |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | The URL of the job queue. Turns the plugin on; read at start-up | Required. Set it in every process (web, jobs, rake) |

| Item | Description | Where to change |
| --- | --- | --- |
| Queues | Redmine's queues `default` and `mailers` both go to the job queue | Fixed (set by the plugin) |
| Allowed job classes | A message for a class not on the list is not run (the gem's `job_class_allowlist`). The list is below | Other plugins add classes with `RedmineAwsSqsBoot.allow_job` |
| The dead-letter queue | The plugin reads the dead-letter queue and `maxReceiveCount` from it (`GetQueueAttributes`). There is no setting of its own | The job queue's redrive policy |

### Allowed job classes

The queue runs only these job classes:

- `Mailer::DeliveryJob` (every email)
- `DestroyProjectJob` and `DestroyProjectsJob`
- `WebhookJob`
- the jobs of the Redmine Serverless plugins: `AwsS3ReconcileJob` and `AwsSesReimportMailJob`
- the classes other plugins add with `RedmineAwsSqsBoot.allow_job`

### Message deletion

The gem deletes a message after its job succeeds. On Lambda it builds the queue URL from the event's ARN (`https://sqs.<region>.amazonaws.com/...`). For the job queue, the plugin uses `REDMINE_JOBS_QUEUE_URL` instead, so the deletion goes to the same endpoint as the jobs, such as LocalStack or an interface endpoint without private DNS. Other queues keep the URL from the ARN.

### Other settings of the gem

Settings that the plugin does not set, such as the poller's `visibility_timeout` or `max_messages`, can still be given in the gem's environment variables (`AWS_ACTIVE_JOB_SQS_*`).

## AWS resources

| Resource | Settings |
| --- | --- |
| SQS job queue | A standard queue (FIFO queues are not supported by resending). Visibility timeout longer than the time a job may take (on Lambda, six times the function's timeout). A redrive policy to the dead-letter queue after 3 receives. Server-side encryption with SQS-managed keys |
| SQS dead-letter queue | Receives the jobs that failed 3 times. The "Jobs" page moves them back with `StartMessageMoveTask` |
| What runs the jobs | On Lambda: a function with an SQS event source mapping on the job queue, batch size 1 (the handler stops at the first job that fails, and the plugin records the failure of the one message of the invocation). Outside Lambda: a process running the gem's poller |

## IAM permissions

The permissions the plugin needs, with an example policy, are in [iam.md](iam.md).

## Network

| Destination | API | In a VPC without internet access |
| --- | --- | --- |
| SQS | `SendMessage`<br>`ReceiveMessage`<br>`DeleteMessage`<br>`GetQueueAttributes`<br>`GetQueueUrl`<br>`StartMessageMoveTask` | Interface endpoint `com.amazonaws.<region>.sqs`, with private DNS so that `sqs.<region>.amazonaws.com` resolves to it |

## Tests

The tests are in `test/` and run with Redmine's standard mechanism, in Redmine 7.0.3 on PostgreSQL 16 in Docker. AWS is LocalStack when `LOCALSTACK_AUTH_TOKEN` is set (CI uses the organization's secret), and if LocalStack does not start, the run fails. Without the token (pull requests from forks, local runs), the same tests run on moto. The log names the backend. LocalStack has every SQS call the plugin makes, so nothing is mocked there; on moto, which has no `StartMessageMoveTask`, that one test is skipped and the call is covered by SDK response stubs. Unit and functional tests use SDK response stubs.

| Target | What is checked |
| --- | --- |
| Jobs on SQS | A mail job goes to SQS through `aws-activejob-sqs` and runs from the handler that Lambda calls; the mail is sent. Without `REDMINE_JOBS_QUEUE_URL`, Redmine runs jobs as standard |
| The allowlist | A message for a class outside the allowed ones does not run, is recorded and deleted |
| Failure records | A job is recorded on the last receive (from the redrive policy), not before, and not without a redrive policy; the poller's handlers do the same |
| Resending | A recorded job is sent back as it was and runs; a class outside the allowed ones is refused |
| The dead-letter queue | The count and `maxReceiveCount` from the redrive policy; moving it back with `StartMessageMoveTask` on LocalStack (moto does not have it; SDK response stubs cover it there) |
| Connection test and page | `GetQueueAttributes`; the "Jobs" page with the counts, failures, resending, deleting and the DLQ redrive, for administrators only | `bin/test` runs the plugin's tests, then Redmine's tests around jobs (mail, projects, webhooks, administration); `bin/test --redmine` runs every Redmine test with the plugin installed, as the CI does. Serverless's image tests also run a job from an SQS event ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#jobs-redmine_aws_sqs)).

The plugin's tests also write the coverage of the plugin's own files (SimpleCov, Cobertura XML in `coverage/coverage.xml`), which CI uploads to [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_sqs).

```sh
bin/test            # the plugin's tests and Redmine's tests around jobs
bin/test --redmine  # with every Redmine test
bin/lint            # RuboCop
bin/services --down # stops PostgreSQL, moto and LocalStack
```

## To verify

- The failure records and the DLQ redrive on a real queue (the tests use LocalStack or moto)
- The poller's handlers with the gem's poller running as a process (the tests call the handlers)
