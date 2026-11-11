# Redmine AWS SQS

Redmine AWS SQS (`redmine_aws_sqs`) は、Redmine のバックグラウンドジョブを Amazon SQS で動かす Redmine のプラグインです。ジョブは、AWS の公式の gem `aws-activejob-sqs` で SQS に送り、プラグインは、それを運用するのに要るもの (設定、最終的に失敗したジョブの記録、再送信の画面) を追加します。[Serverless](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs) が、Lambda 用のイメージにインストールして使います。Redmine 本体のファイルは書き換えません。今は開発の初期です。

- [導入](setup.md): 動作環境、インストール、設定、AWS リソース、ネットワーク、テスト
- [IAM 権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [管理画面](admin.md): ジョブ

<a id="features"></a>

## 機能

機能ごとに、有効にする条件を持たせます。条件がそろわなければ、Redmine は標準のままにジョブを動かします。

| 機能 | 内容 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| SQS でのジョブ | ActiveJob のキューアダプターを `aws-activejob-sqs` にし、Redmine のキュー (`default`、`mailers`) をジョブキューに向け、Redmine とほかの Redmine AWS のプラグインのジョブクラス (`Mailer::DeliveryJob`、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob`、`AwsS3ReconcileJob`、`AwsSesReimportMailJob`) だけを実行させる | `REDMINE_JOBS_QUEUE_URL` がある | [setup.md](setup.md#configuration) |
| ジョブの失敗の記録 | 最終的に失敗したジョブ (デッドレターキューに移る前の最後の受信、実行できないメッセージ) を、中身とエラーといっしょに記録し、再送信できるようにする | 同上 | [admin.md](admin.md#jobs) |
| 管理画面 | [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu) の「AWS」メニューの「ジョブ」のタブ。キューの件数、失敗したジョブ、再送信、DLQ 再処理 | システム管理者 | [admin.md](admin.md) |

<a id="running-the-jobs"></a>

## ジョブを動かすもの

キューからジョブを取り出して動かすものが要ります。どちらの形でも、プラグインは失敗を記録します。

- **AWS Lambda では、** SQS のイベントソースを持つ関数が、gem の `Aws::ActiveJob::SQS::LambdaHandler.job_handler` で動かします。Serverless では `redmine-worker` がこれに当たり、ハンドラーはプラグインではなくイメージで設定します。
- **Lambda 以外では、** gem のポーラー (`aws_active_job_sqs`) を、ECS や EC2 などで別のプロセスとして動かします。

<a id="other-plugins"></a>

## ほかのプラグイン

自分のジョブクラスを持つプラグインは、`init.rb` で `RedmineAws::SQS::Boot.allow_job('クラス名')` を呼び、実行してよいクラスに追加します。

どのメールのエラーを再試行するかは、[Redmine AWS SES](https://redmine-kit.github.io/redmine_aws_ses/ja/) が決めます。最終的に失敗したメールは、ほかのジョブと同じくここに記録します。「ジョブ」の画面は、このプラグインが必要とする [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) の「AWS」の画面のタブになり、SQS の確認はその「ステータス」のタブの接続テストに加わります。

<a id="in-serverless"></a>

## Serverless での設定

キューアダプター、キュー、実行を許可するジョブクラスはプラグインが設定するので、イメージには、そのための `config/additional_environment.rb` も `config/aws_active_job_sqs.yml` も要りません ([Serverless の lambda.md](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs))。

<a id="code-layout"></a>

## コード構成

コードは、Redmine AWS の名前空間 `RedmineAws` の下の `RedmineAws::SQS` です。`boot/redmine_aws_sqs.rb` (`RedmineAws::SQS::Boot`) が、キューアダプターと gem の設定を受け持ちます。プラグインは gem でもあるので、Bundler がこのファイルを Rails の初期化より前に読み込みます ([setup.md](setup.md#installation))。ほかは Redmine が読み込む `lib/redmine_aws/sqs.rb`、`lib/redmine_aws/sqs/`、`app/`、`db/` にあり、`init.rb` が有効にします。「AWS」の管理メニュー、そのタブ、接続テストは、プラグインが必要とする [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) (`redmine_aws`) が持ちます。

<a id="database-tables"></a>

## データベーステーブル

失敗の記録のテーブル (`aws_sqs_job_failures`) を追加します。デプロイでは `redmine:plugins:migrate` も実行します。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine AWS SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
