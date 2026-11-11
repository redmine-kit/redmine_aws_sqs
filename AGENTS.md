# AGENTS.md

Guidelines for people and coding agents working in this repository. See [README.md](README.md) for an overview and [docs/](docs/README.md) for the design.

## What this project does

Redmine AWS SQS (`redmine_aws_sqs`) is a Redmine plugin that runs Redmine's background jobs on Amazon SQS, records the jobs that fail for the last time, and adds the "Jobs" administration page. It works with or without AWS Lambda. [Serverless](https://github.com/redmine-kit/serverless) installs it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless). It is in early development.

## Rules

- **Redmine's extension points only:** do not edit Redmine's own files. Keep Redmine's standard behaviour wherever possible.
- **Off without its settings:** without the job queue's URL, Redmine runs jobs as standard.
- **Official gem:** jobs go to SQS through AWS's `aws-activejob-sqs`; the plugin does not write its own queue adapter.
- **Tests:** added code has tests, run with Redmine's own mechanism (`bin/test` runs them in Docker with PostgreSQL and moto; [setup.md](docs/setup.md#tests)). The test plan is in Serverless ([testing.md](https://github.com/redmine-kit/serverless/blob/main/docs/testing.md#jobs-redmine_aws_sqs)).
- **Code layout:** `boot/` holds what must be in place before Rails initializes (Bundler loads it; module `RedmineAwsSqsBoot`), `lib/`, `app/` and `db/` the rest (Redmine loads them; `init.rb` calls `RedmineAwsSqs.setup`).
- **Requires redmine_aws:** the "AWS" item of the administration menu with its tabs and connection checks, and the test support, come from [redmine_aws](https://github.com/redmine-kit/redmine_aws) (`RedmineAws::Admin`, `RedmineAws::AdminTab`, `RedmineAws::TestHelper`, `RedmineAws::ScreenshotCase`). Don't copy them into this plugin. `bin/test` and `bin/screenshots` load redmine_aws from `../redmine_aws`, or from `REDMINE_AWS_DIR`.
- **No secrets in the repository.**

## Documentation

- **Two languages.** English is the source (`README.md`, `docs/`); the Japanese translation is `README.ja.md` and `docs/ja/`, with the same file names. Change both together.
- **Layout.** The READMEs stay short. The details go in `docs/`, published at https://redmine-kit.github.io/redmine_aws_sqs/ with [redmine-kit/docs-skeleton](https://github.com/redmine-kit/docs-skeleton). `docs/README.md` has the overview and the features, `docs/setup.md` the sections Requirements, Installation, Configuration, AWS resources, IAM permissions, Network, Tests and To verify, in this order (the same in every Redmine Serverless plugin; IAM permissions there is one line that points to `docs/iam.md`), `docs/iam.md` the sections Permissions, Example policy, Resource-based policies and Not checked yet. Links to the documentation of Serverless and the other plugins are absolute URLs.
- **Anchors in Japanese.** Put `<a id="..."></a>` with the English heading's anchor before each Japanese heading.
- **Facts.** State only what has been checked, with the date and the source. Mark what has not been checked yet.
- **Japanese wording.** Plain, precise Japanese. Keep established technical terms. Do not use "版" for a version, write "通知" rather than "知らせ", "確認" rather than "確かめ", and "インストール" rather than "入れ方".

## Commits

- English, imperative mood, 72 characters or fewer in the first line, no trailing period.
- One purpose per commit.
- Do not rewrite pushed history.
