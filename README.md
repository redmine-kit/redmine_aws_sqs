# Redmine AWS SQS

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_aws_sqs/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_aws_sqs/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_aws_sqs?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_aws_sqs)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_aws_sqs?label=License)](LICENSE)
[![Tested with AWS Emulator](https://img.shields.io/badge/Tested%20with-AWS%20Emulator-232F3E)](https://github.com/aws/aws-emulator)

A Redmine plugin that runs Redmine's background jobs on Amazon SQS: the settings for AWS's `aws-activejob-sqs` (queues and the job classes it may run), records of jobs that fail for the last time with resending, and an administration page for the queues. It works with or without AWS Lambda, and requires [Redmine AWS](https://github.com/redmine-kit/redmine_aws), which adds the "AWS" administration menu. [Serverless](https://github.com/redmine-kit/serverless) uses it together with [Redmine AWS Lambda](https://github.com/redmine-kit/redmine_aws_lambda).

[日本語](README.ja.md)

> **Status:** early development. It is implemented and tested on Redmine 7.0.3.

## Documentation

- Website: https://redmine-kit.github.io/redmine_aws_sqs/ (日本語: https://redmine-kit.github.io/redmine_aws_sqs/ja/)
- Markdown: [docs/README.md](docs/README.md) (日本語: [docs/ja/README.md](docs/ja/README.md)), with [setup](docs/setup.md), [IAM permissions](docs/iam.md) and the [administration page](docs/admin.md)

## Sponsors

<a href="https://www.keyselect.co.jp/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/keyselect-logo-dark.svg">
    <img alt="KEY SELECT" src=".github/assets/keyselect-logo.svg" width="136" height="29">
  </picture>
</a>

## License

Redmine AWS SQS is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE). An unofficial Redmine plugin.
