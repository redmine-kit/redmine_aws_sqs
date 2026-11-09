# Setup

What a Redmine needs to use Redmine Serverless SQS: installation, configuration, the AWS resources it expects, IAM permissions and network access. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates.

## Requirements

- Redmine 7.0 or later.
- AWS's gem `aws-activejob-sqs` 1.2 or later (a dependency of the gem; with a checkout, the plugin's `Gemfile` adds it).
- Something that runs the jobs: on AWS Lambda, a function with an SQS event source and the handler `Aws::ActiveJob::SQS::LambdaHandler.job_handler`; outside Lambda, the gem's poller (`aws_active_job_sqs`).

## Installation

1. Get the plugin into `plugins/redmine_serverless_sqs` of Redmine 7.0: the gem below, or a checkout of this repository.
2. Add the plugin to `Gemfile.local` as a gem, and run `bundle install`. Bundler then loads `boot/redmine_serverless_sqs.rb` before Rails initializes: the queue adapter must be set by then, and Redmine's own loading of plugins (`init.rb`) comes too late for it. With a checkout, add it by path:

   ```ruby
   # Redmine's Gemfile.local
   gem 'redmine_serverless_sqs', path: 'plugins/redmine_serverless_sqs'
   ```

3. Run `bin/rake redmine:plugins:migrate`. It creates the table of failure records (`serverless_job_failures`).
4. Remove settings of `aws-activejob-sqs` made elsewhere, if any: a queue adapter set in `config/additional_environment.rb`, and `config/aws_active_job_sqs.yml`. The plugin sets both.

### Gem

Each version tag (`v*`) publishes the plugin as a gem to GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`; `.github/workflows/gem.yml`). The gem holds the run-time files (`init.rb`, `boot/`, `lib/`, `app/`, `config/`, `db/`, `LICENSE`); the plugin's `Gemfile` is not in it. Redmine loads plugins only from `plugins/`, so the installed gem is linked there:

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_serverless_sqs'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <user>:<token>   # or BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_serverless_sqs)" plugins/redmine_serverless_sqs
```

- **Access:** installing from GitHub Packages needs a GitHub token with `read:packages`, even for a public package. A workflow of another repository reads it with its `GITHUB_TOKEN` (`packages: read`) once the package's settings ("Manage Actions access") give that repository Read.

## Configuration

| Setting | Where | Contents |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | Environment variable of every process (web, jobs, rake) | The URL of the job queue. Turns the plugin on; read at start-up |
| Queues | Set by the plugin | Redmine's queues `default` and `mailers` both go to the job queue |
| Allowed job classes | Set by the plugin | `Mailer::DeliveryJob` (every email), `DestroyProjectJob`, `DestroyProjectsJob`, `WebhookJob`, and the classes other plugins add with `RedmineServerlessSqsBoot.allow_job`. A message for another class is not run (the gem's `job_class_allowlist`) |
| The dead-letter queue | The job queue's redrive policy | The plugin reads the dead-letter queue and `maxReceiveCount` from it (`GetQueueAttributes`). There is no setting of its own |

- **Message deletion:** The gem deletes a message after its job succeeds. On Lambda it builds the queue URL from the event's ARN (`https://sqs.<region>.amazonaws.com/...`), so the function must reach that address (checked in Serverless's image tests on 2026-11-09).
- **Other settings of the gem:** Settings that the plugin does not set (for example, the poller's `visibility_timeout` or `max_messages`) can still be given in the gem's environment variables (`AWS_ACTIVE_JOB_SQS_*`).

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
| SQS | `SendMessage`, `ReceiveMessage`, `DeleteMessage`, `GetQueueAttributes`, `GetQueueUrl`, `StartMessageMoveTask` | Interface endpoint `com.amazonaws.<region>.sqs`, with private DNS so that `sqs.<region>.amazonaws.com` resolves to it |

## Tests

The tests are in `test/` and run with Redmine's standard mechanism, in Redmine 7.0.3 on PostgreSQL 16 and moto in Docker. Unit and functional tests use SDK response stubs; the integration tests run on moto: a mail job goes to SQS through the adapter and runs from the handler that Lambda calls, a class outside the allowed ones does not run, and a recorded job is resent and runs. `bin/test` runs the plugin's tests, then Redmine's tests around jobs (mail, projects, webhooks, administration); `bin/test --redmine` runs every Redmine test with the plugin installed, as the CI does. Serverless's image tests also run a job from an SQS event ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#jobs-redmine_serverless_sqs)).

The plugin's tests also write the coverage of the plugin's own files (SimpleCov, Cobertura XML in `coverage/coverage.xml`), which CI uploads to [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_sqs).

```sh
bin/test            # the plugin's tests and Redmine's tests around jobs
bin/test --redmine  # with every Redmine test
bin/lint            # RuboCop
bin/services --down # stops PostgreSQL and moto
```

## To verify

- The failure records and moving the dead-letter queue back on a real queue (the tests use moto)
- The poller's handlers with the gem's poller running as a process (the tests call the handlers)
