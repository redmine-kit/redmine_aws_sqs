# Setup

What a Redmine needs to use Redmine Kit AWS SQS: installation, configuration, the AWS resources it expects, IAM permissions and network access. [Serverless](https://redmine-kit.github.io/serverless/) sets all of this up with CloudFormation; this page is for setting it up by hand, or for checking what Serverless creates.

## Requirements

- Redmine 7.0 or later.
- AWS's gem `aws-activejob-sqs` 1.2 or later (a dependency of the gem; with a checkout, the plugin's `Gemfile` adds it).
- Something that runs the jobs: on AWS Lambda, a function with an SQS event source and the handler `Aws::ActiveJob::SQS::LambdaHandler.job_handler`; outside Lambda, the gem's poller (`aws_active_job_sqs`).

### Required plugins

| Plugin | Used for |
| --- | --- |
| [Redmine Kit AWS](https://github.com/redmine-kit/redmine_aws) | the AWS administration menu and the settings shared by the AWS plugins |

Without it, Redmine stops at boot and names it. Installed as a gem, this plugin installs it
([Installation](#installation)).

### Optional plugins

| Plugin | With it |
| --- | --- |
| [Redmine Kit Help](https://github.com/redmine-kit/redmine_help) | this plugin's help in the Help panel |
| [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) | the new UI's screen of the Jobs tab ([admin.md](admin.md#in-the-new-ui)) |

## Installation

1. Install the plugin as a gem ([Gem](#gem)), or put checkouts of it and of [Redmine Kit AWS](https://redmine-kit.github.io/redmine_aws/), which it requires, in Redmine's `plugins/` ([Without the gem](#without-the-gem)). The order doesn't matter: at boot, Redmine stops and names `redmine_kit_aws` when it is missing ([Required plugins](#required-plugins)).
2. Run `bundle install` in Redmine's folder.
3. Run the plugin's migrations:

   ```sh
   bin/rails redmine:plugins:migrate RAILS_ENV=production
   ```

   They create the table of failure records (`aws_sqs_job_failures`) and the table of the queue counts the "Jobs" tab shows (`aws_sqs_snapshots`).
4. Remove settings of `aws-activejob-sqs` made elsewhere, if any: a queue adapter set in `config/additional_environment.rb`, and `config/aws_active_job_sqs.yml`. The plugin sets both.
5. Restart Redmine.

### Gem

**As a gem** (first choice): add it to Redmine's `Gemfile.local`, in a block of Redmine Kit's registry on GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`, where `bin/release` publishes it: [Releasing](#releasing)). Bundler takes the plugins it requires from there too ([Required plugins](#required-plugins)), and never takes these gems from rubygems.org. The registry needs a GitHub token with `read:packages`, even for a public package, given to Bundler in the environment variable `BUNDLE_RUBYGEMS__PKG__GITHUB__COM` (`<user>:<token>`), never in a file of a repository.

```ruby
# Redmine's Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_kit_aws_sqs'
end
```

**From the repositories** (for development), Bundler takes the gems from git instead; it doesn't take the plugins a gem requires from git, so their lines come too:

```ruby
# Redmine's Gemfile.local
gem 'redmine_kit_aws', git: 'https://github.com/redmine-kit/redmine_aws.git', branch: 'main'
gem 'redmine_kit_aws_sqs', git: 'https://github.com/redmine-kit/redmine_aws_sqs.git', branch: 'main'
```

Bundler requires `boot/redmine_kit_aws_sqs.rb`, which hands the gem's folder to Redmine's plugin loader (and, from the gems it depends on, Redmine Kit AWS's): Redmine runs the gem's `init.rb`, serves its assets, strings, views and migrations, adds its `lib/` and `app/` to Rails' code loader and draws its routes, as for a plugin in `plugins/`, so no link in `plugins/` is needed. A folder of the same id in `plugins/` wins over the gem. The file also does what must be in place before Rails initializes: the queue adapter must be set by then, and Redmine runs `init.rb` too late for it. The gem holds the run-time files; the plugin's `Gemfile` is not in it.

### Without the gem

Clone the repositories into Redmine's `plugins/`, in folders named after the plugins' ids, which differ from the repositories' names:

```sh
git clone https://github.com/redmine-kit/redmine_aws.git plugins/redmine_kit_aws
git clone https://github.com/redmine-kit/redmine_aws_sqs.git plugins/redmine_kit_aws_sqs
```

The plugin's `Gemfile`, which Redmine's `Gemfile` loads, names the plugin by its path, so that Bundler loads `boot/redmine_kit_aws_sqs.rb` before Rails initializes as the gem's does, and Redmine Kit AWS by the path of its checkout next to it (each unless `Gemfile.local` or another plugin's `Gemfile` names it already). No line in `Gemfile.local` is needed.

## Configuration

| Key | Description | Parameter |
| --- | --- | --- |
| `REDMINE_SQS_QUEUE_URL` | The URL of the job queue. Turns the plugin on; read at start-up | Required. Set it in every process (web, jobs, rake) |

| Item | Description | Where to change |
| --- | --- | --- |
| Queues | Redmine's queues `default` and `mailers` both go to the job queue | Fixed (set by the plugin) |
| Allowed job classes | A message for a class not on the list is not run (the gem's `job_class_allowlist`). The list is below | Other plugins add classes with `RedmineKit::Aws::Sqs::Boot.allow_job` |
| The dead-letter queue | The plugin reads the dead-letter queue and `maxReceiveCount` from it (`GetQueueAttributes`). There is no setting of its own | The job queue's redrive policy |

### Allowed job classes

The queue runs only these job classes:

- `Mailer::DeliveryJob` (every email)
- `DestroyProjectJob` and `DestroyProjectsJob`
- `WebhookJob`
- the jobs of the other Redmine Kit AWS plugins: `AwsS3ReconcileJob` and `AwsSesReimportMailJob`
- the classes other plugins add with `RedmineKit::Aws::Sqs::Boot.allow_job`

### Message deletion

The gem deletes a message after its job succeeds. On Lambda it builds the queue URL from the event's ARN (`https://sqs.<region>.amazonaws.com/...`). For the job queue, the plugin uses `REDMINE_SQS_QUEUE_URL` instead, so the deletion goes to the same endpoint as the jobs, such as an interface endpoint without private DNS, or an emulator in tests. Other queues keep the URL from the ARN.

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

The tests are in `test/` and run with Redmine's standard mechanism, in Redmine 7.0.3 on PostgreSQL 16, in Apple container when it is installed and running, else in Docker (`CONTAINER_CLI=container` or `docker` chooses). At most two test runs of the redmine-kit repositories run at once on a machine (`TEST_SLOTS`); a run waits for a free slot. SQS is [AWS Emulator](https://docs.aws.amazon.com/emulator/latest/userguide/) (`bin/aws_emulator`; `test/compose.yml` in Docker), installed from AWS's package at the version pinned in `test/aws-emulator/Dockerfile`, with its telemetry off; the log names the version. It has every SQS call the plugin makes, so the integration tests mock nothing. Unit and functional tests use SDK response stubs.

A run stops the service containers it started (it doesn't remove them) when it ends, whether the tests pass, fail or are interrupted. Containers that were running before the run, or that another run of this repository still uses, are left running. `KEEP_SERVICES=1` keeps them running after the run.

The plugin's tests run on an internal network and cannot reach AWS; a test fails if they can. The emulator's certificate names only `127.0.0.1` and `localhost`, so the tests reach it there: in Docker they run in its network namespace; Apple container can't share one, so they forward `127.0.0.1:9297` to the emulator's container (`bin/aws_emulator`, `test/aws_forward.rb`) and trust the certificate copied out of it. Redmine's own tests, which call no AWS API but resolve names on the internet (webhooks), run on another network. The emulator answers queue URLs on the public SQS host (`https://sqs.<region>.amazonaws.com/...`), which it does not serve, so the tests put the queue URLs it answers on its endpoint (`test/test_helper.rb`; [the emulator's issue](https://github.com/aws/aws-emulator/blob/7753983c6e495ec3612695b1336bf4936fc7b7fd/issues/things-that-do-not-work/20261109T191027Z-sqs-queue-url-addressing-diverges-from-aws-createqueue.md)).

| Target | What is checked |
| --- | --- |
| Jobs on SQS | A mail job goes to SQS through `aws-activejob-sqs` and runs from the handler that Lambda calls; the mail is sent. Without `REDMINE_SQS_QUEUE_URL`, Redmine runs jobs as standard |
| The allowlist | A message for a class outside the allowed ones does not run, is recorded and deleted |
| Failure records | A job is recorded on the last receive (from the redrive policy), not before, and not without a redrive policy; the poller's handlers do the same. A `JSON::ParserError` that the job itself raises is the job's error, retried, not a message that can never run |
| Resending | A recorded job is sent back as it was and runs; a class outside the allowed ones is refused |
| Refreshing the counts | `redmine_kit:aws:sqs:refresh` stores the queue counts; it fails when `REDMINE_SQS_QUEUE_URL` is not set or SQS can't be read, and the error's class is stored for the page |
| Keeping records | `redmine_kit:aws:sqs:prune` deletes the records older than 90 days, or than `DAYS`; a `DAYS` that is not a whole number from 1 to 99999 stops the task with a message and deletes nothing |
| The dead-letter queue | The count and `maxReceiveCount` from the redrive policy; moving it back with `StartMessageMoveTask` |
| Connection test and page | `GetQueueAttributes`; the "Jobs" page with the stored counts (the page calls no AWS API; "Refresh" does), failures, resending, deleting and the DLQ redrive, for administrators only |
| The network | The plugin's tests cannot open a connection to SQS or STS on AWS |
| Code loading | In new processes: `zeitwerk:check` passes, and Redmine Kit AWS and this plugin start with the boot file loaded |

`bin/test` runs the plugin's tests with [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) installed (from the checkout next to this one, `../redmine_kit_ui` at `HEAD`; `REDMINE_KIT_UI` and `REDMINE_KIT_UI_REF` choose another), then without it, then Redmine's tests around jobs (mail, projects, webhooks, administration); `bin/test --redmine` runs every Redmine test with the plugin installed, as the CI does. Serverless's image tests also run a job from an SQS event ([Serverless testing.md](https://redmine-kit.github.io/serverless/testing.html#jobs-redmine_kit_aws_sqs)).

CI runs the lint and the tests on Ruby 3.2 and 4.0; locally, `TEST_RUBY=3.2 bin/test` (or `bin/lint`) runs them on Ruby 3.2.

`bin/test-gem` checks the gem as the template of the organization's plugins does: it builds the gems of the plugin and of Redmine Kit AWS from the checkouts, takes the checkouts out of `plugins/`, installs the gems as [Gem](#gem) says and starts Redmine with every file loaded (`zeitwerk:check`, and the production environment, which loads them at start-up), checking that each plugin comes from its gem's folder with its boot file, code, routes, migrations and assets; then again with the checkouts back in `plugins/`, which win. CI runs it too, so a file missing from the gem fails before Serverless installs it.

The tests need Redmine Kit AWS: a checkout of [redmine_kit_aws](https://github.com/redmine-kit/redmine_aws) next to this repository (`../redmine_kit_aws`), or its path in `REDMINE_KIT_AWS_DIR`. CI checks it out.

With `COVERAGE=1`, the plugin's tests also write the coverage of the plugin's own files (SimpleCov, Cobertura XML in `coverage/coverage.xml`) and run in one process. CI sets it on Ruby 4.0 and uploads the report to [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_sqs) with the flag `plugin`. The upload authenticates with OIDC (`id-token: write`), so no token is stored as a secret. Codecov's statuses are informational and never fail a commit or a pull request (`codecov.yml`).

```sh
bin/test            # the plugin's tests and Redmine's tests around jobs
bin/test --redmine  # with every Redmine test
COVERAGE=1 bin/test # with the coverage in coverage/coverage.xml
REDMINE_KIT_AWS_DIR=<dir> bin/test  # with redmine_kit_aws from <dir>
bin/test-gem        # the gems: built, installed, booted from the gems, then from plugins/
bin/lint            # RuboCop
bin/services --down # stops PostgreSQL and AWS Emulator
```

The new UI's module is checked in `frontend/` with Node.js (the version in `frontend/.nvmrc`); `.npmrc` has `ignore-scripts=true`, and `@redmine-kit/ui` and `@redmine-kit/plugin` come from the checkout of the ui repository next to this one (`../../ui/packages/…`):

```sh
cd frontend
npm install
npm run check       # type check, the components' tests (vitest), the build, kit-check-ui, the Storybook's build
npm run storybook   # the Storybook of the tab's states, on port 6008
```

## Releasing

`bin/release` publishes the gem of the gemspec's version to Redmine Kit's registry on GitHub Packages, from a clean
`main` only: the version must be newer than the last tag `v<version>`, the required plugins must resolve from the
registry at their ranges (`config/dependencies.yml`), and `bin/lint`, `bin/test` and `bin/test-gem` must pass. It
pushes with the key `github` of `~/.gem/credentials` (`:github: Bearer <token>`, a token with `write:packages`) and
reads the registry with `BUNDLE_RUBYGEMS__PKG__GITHUB__COM`; no token goes into the repository or the output. It makes
the signed tag `v<version>` and prints the command that pushes it. Versions are semantic: a change that breaks a plugin
using this one raises the major version (the minor one before 1.0), and the ranges in the plugins that require it.

## To verify

- The failure records and the DLQ redrive on a real queue (the tests use AWS Emulator)
- The poller's handlers with the gem's poller running as a process (the tests call the handlers)
