# Redmine AWS SQS

Redmine AWS SQS(`redmine_aws_sqs`)は、Redmine のバックグラウンドのジョブを Amazon SQS で動かす Redmine のプラグインです。ジョブは、AWS の公式の gem `aws-activejob-sqs` で SQS に送り、プラグインは、それを運用するのに要るもの(設定、最後に失敗したジョブの記録、再送信の画面)を追加します。[Serverless](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs) が、Lambda 用のイメージに入れて使います。Redmine 本体のファイルは書き換えません。今は開発の初期です。

- [導入](setup.md): 動作環境、インストール、設定、AWS リソース、ネットワーク、テスト
- [IAM 権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [管理画面](admin.md): ジョブ

<a id="features"></a>

## 機能

機能ごとに、有効にする条件を持たせます。条件がそろわなければ、Redmine は標準のままにジョブを動かします。

| 機能 | 内容 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| SQS でのジョブ | ActiveJob のキューのアダプターを `aws-activejob-sqs` にし、Redmine のキュー(`default`、`mailers`)をジョブのキューに向け、Redmine と Redmine Serverless のプラグインのジョブのクラス(`Mailer::DeliveryJob`、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob`、`AwsS3ReconcileJob`、`AwsSesReimportMailJob`)だけを実行させる | `REDMINE_JOBS_QUEUE_URL` がある | [setup.md](setup.md#configuration) |
| ジョブの失敗の記録 | 最後に失敗したジョブ(デッドレターキューに移る前の最後の受け取り、実行できないメッセージ)を、中身とエラーといっしょに記録し、再送信できるようにする | 同上 | [admin.md](admin.md#jobs) |
| 管理画面 | 共有の「Serverless」のメニューの「ジョブ」のタブ。キューの件数、失敗したジョブ、再送信、DLQ 再処理 | 管理者 | [admin.md](admin.md) |

<a id="running-the-jobs"></a>

## ジョブを動かすもの

キューからジョブを取り出して動かすものが要ります。どちらの形でも、プラグインは失敗を記録します。

- **AWS Lambda では、** SQS のイベントソースを持つ関数が、gem の `Aws::ActiveJob::SQS::LambdaHandler.job_handler` で動かします。Serverless では `redmine-worker` がこれに当たり、ハンドラーはプラグインではなくイメージで設定します。
- **Lambda 以外では、** gem の取り出し役(`aws_active_job_sqs`)を、ECS や EC2 などで別のプロセスとして動かします。

<a id="other-plugins"></a>

## ほかのプラグイン

自分のジョブのクラスを持つプラグインは、`init.rb` で `RedmineAwsSqsBoot.allow_job('クラス名')` を呼び、実行してよいクラスに追加します。

どのメールのエラーをやり直すかは、[Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。最後に失敗したメールは、ほかのジョブと同じくここに記録します。[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/) をインストールすると、「ジョブ」の画面はその「Serverless」の画面のタブになり、SQS の確認はその接続テストに加わります。

<a id="in-serverless"></a>

## Serverless での設定

キューのアダプター(`config/additional_environment.rb`)と、キューと実行を許可するジョブクラス(`config/aws_active_job_sqs.yml`)は、以前はイメージが設定していました。今はプラグインが受け持ちます([Serverless の lambda.md](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs))。

<a id="code-layout"></a>

## コード構成

`boot/redmine_aws_sqs.rb` が、キューのアダプターと gem の設定を受け持ちます。プラグインは gem でもあるので、Bundler がこのファイルを Rails の初期化より前に読み込みます([setup.md](setup.md#installation))。ほかは Redmine が読み込む `lib/redmine_aws_sqs/`、`app/`、`db/` にあり、`init.rb` が有効にします。

<a id="database-tables"></a>

## データベーステーブル

失敗の記録のテーブル(`aws_sqs_job_failures`)を追加します。デプロイでは `redmine:plugins:migrate` も実行します。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine AWS SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
