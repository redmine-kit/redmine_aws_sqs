# Redmine Serverless SQS

Redmine のバックグラウンドのジョブを Amazon SQS で動かす Redmine のプラグインです。AWS の `aws-activejob-sqs` の設定(キューと、実行してよいジョブのクラス)、最後に失敗したジョブの記録と送り直し、キューの管理画面を持ちます。AWS Lambda でも、Lambda 以外でも動きます。[Serverless](https://github.com/redmine-kit/serverless) は、[Redmine Serverless](https://github.com/redmine-kit/redmine_serverless) といっしょに使います。

[English](README.md)

> **状態:** 設計段階です。リポジトリには設計の資料だけがあり、まだ何も実装していません。

<a id="documentation"></a>

## ドキュメント

- Web サイト: https://redmine-kit.github.io/redmine_serverless_sqs/ja/ (English: https://redmine-kit.github.io/redmine_serverless_sqs/)
- Markdown: [docs/ja/README.md](docs/ja/README.md) (English: [docs/README.md](docs/README.md))。[準備](docs/ja/setup.md)、[IAM の権限](docs/ja/iam.md)と[管理画面](docs/ja/admin.md)があります。

<a id="license"></a>

## ライセンス

Redmine Serverless SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](LICENSE) を参照してください。Redmine projectとは関係ありません。
