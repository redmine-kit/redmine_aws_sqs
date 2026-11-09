# Redmine Serverless SQS

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_sqs/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_sqs/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_sqs?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_serverless_sqs)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_sqs?label=License)](LICENSE)

A Redmine plugin that runs Redmine's background jobs on Amazon SQS: the settings for AWS's `aws-activejob-sqs` (queues and the job classes it may run), records of jobs that fail for the last time with resending, and an administration page for the queues. It works with or without AWS Lambda; [Serverless](https://github.com/redmine-kit/serverless) uses it together with [Redmine Serverless](https://github.com/redmine-kit/redmine_serverless).

[日本語](README.ja.md)

> **Status:** early development. Jobs on SQS, the failure records and the "Jobs" page are implemented and tested on Redmine 7.0.3 with moto.

## Documentation

- Website: https://redmine-kit.github.io/redmine_serverless_sqs/ (日本語: https://redmine-kit.github.io/redmine_serverless_sqs/ja/)
- Markdown: [docs/README.md](docs/README.md) (日本語: [docs/ja/README.md](docs/ja/README.md)), with [setup](docs/setup.md), [IAM permissions](docs/iam.md) and the [administration page](docs/admin.md)

## License

Redmine Serverless SQS is released under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE). Not affiliated with the Redmine project.
