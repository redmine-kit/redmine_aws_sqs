# Redmine Serverless SQS

[![CI](https://img.shields.io/github/actions/workflow/status/redmine-kit/redmine_serverless_sqs/ci.yml?branch=main&label=CI)](https://github.com/redmine-kit/redmine_serverless_sqs/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/redmine-kit/redmine_serverless_sqs)](https://codecov.io/gh/redmine-kit/redmine_serverless_sqs)
[![License](https://img.shields.io/github/license/redmine-kit/redmine_serverless_sqs)](LICENSE)

Redmine のバックグラウンドのジョブを Amazon SQS で動かす Redmine のプラグインです。AWS の `aws-activejob-sqs` の設定(キューと、実行してよいジョブのクラス)、最後に失敗したジョブの記録と送り直し、キューの管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine Serverless](https://github.com/redmine-kit/redmine_serverless) といっしょに使います。

[English](README.md)

> **状態:** 開発の初期です。SQS でのジョブ、失敗の記録、「ジョブ」の画面を実装し、Redmine 7.0.3 と moto でテストしています。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_serverless_sqs/ja/ (English: https://redmine-kit.github.io/redmine_serverless_sqs/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[準備](docs/ja/setup.md)、[IAM の権限](docs/ja/iam.md)と[管理画面](docs/ja/admin.md)があります。

<a id="license"></a>

## ライセンス

Redmine Serverless SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine projectとは関係ありません。
