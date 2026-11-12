# Redmine AWS SQS

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_aws_sqs/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_aws_sqs/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_aws_sqs?label=Coverage)](https://codecov.io/gh/redmine-kit/redmine_aws_sqs)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_aws_sqs?label=License)](LICENSE)
[![Tested with AWS Emulator](https://img.shields.io/badge/Tested%20with-AWS%20Emulator-232F3E)](https://github.com/aws/aws-emulator)

Redmine のバックグラウンドジョブを Amazon SQS で動かす Redmine のプラグインです。AWS の `aws-activejob-sqs` の設定 (キューと、実行を許可するジョブクラス)、最終的に失敗したジョブの記録と再送信、キューの管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。「AWS」の管理メニューを追加する [Redmine AWS](https://github.com/redmine-kit/redmine_aws) が必要です。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine AWS Lambda](https://github.com/redmine-kit/redmine_aws_lambda) といっしょに使います。

[English](README.md)

> **状態:** 開発の初期です。実装し、Redmine 7.0.3 でテストしています。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_aws_sqs/ja/ (English: https://redmine-kit.github.io/redmine_aws_sqs/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[導入](docs/ja/setup.md)、[IAM 権限](docs/ja/iam.md)と[管理画面](docs/ja/admin.md)があります。

<a id="sponsors"></a>

## スポンサー

<a href="https://www.keyselect.co.jp/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/keyselect-logo-dark.svg">
    <img alt="KEY SELECT" src=".github/assets/keyselect-logo.svg" width="136" height="29">
  </picture>
</a>

<a id="license"></a>

## ライセンス

Redmine AWS SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine の非公式のプラグインです。
