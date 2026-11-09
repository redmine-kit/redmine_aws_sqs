# Redmine Serverless SQS

Redmine Serverless SQS(`redmine_serverless_sqs`)は、Redmine のバックグラウンドのジョブを Amazon SQS で動かす Redmine のプラグインです。ジョブは、AWS の公式の gem `aws-activejob-sqs` で SQS に送り、プラグインは、それを運用するのに要るもの(設定、最後に失敗したジョブの記録、送り直しの画面)を足します。[Serverless](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs) が、Lambda 用のイメージに入れて使います。Redmine 本体のファイルは書き換えません。今は開発の初期です(バージョン 0.1.2)。

- [導入](setup.md): 動作環境、インストール、設定、AWS のリソース、ネットワーク、テスト
- [IAM の権限](iam.md): 権限、ポリシーの例、リソースベースのポリシー
- [管理画面](admin.md): ジョブ

<a id="features"></a>

## 機能

機能ごとに、有効にする条件を持たせます。条件がそろわなければ、Redmine は標準のままにジョブを動かします。

| 機能 | 中身 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| SQS でのジョブ | ActiveJob のキューのアダプターを `aws-activejob-sqs` にし、Redmine のキュー(`default`、`mailers`)をジョブのキューに向け、Redmine と Redmine Serverless のプラグインのジョブのクラス(`Mailer::DeliveryJob`、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob`、`ServerlessS3ReconcileJob`、`ServerlessReimportMailJob`)だけを実行させる | `REDMINE_JOBS_QUEUE_URL` がある | [setup.md](setup.md#configuration) |
| ジョブの失敗の記録 | 最後に失敗したジョブ(デッドレターキューに移る前の最後の受け取り、実行できないメッセージ)を、中身とエラーといっしょに記録し、送り直せるようにする | 同上 | [admin.md](admin.md#jobs) |
| 管理画面 | 共有の「Serverless」のメニューの「ジョブ」のタブ。キューの件数、失敗したジョブ、送り直し、デッドレターキューの戻し | 管理者 | [admin.md](admin.md) |

- **Lambda でも、Lambda 以外でも:** キューからジョブを取り出して動かすものが要ります。AWS Lambda では、SQS のイベントソースを持つ関数が、gem の `Aws::ActiveJob::SQS::LambdaHandler.job_handler` で動かします(Serverless では `redmine-worker`。ハンドラーは、プラグインではなくイメージで設定します)。Lambda 以外では、gem の取り出し役(`aws_active_job_sqs`)を、ECS や EC2 などで別のプロセスとして動かします。どちらでも、失敗を記録します。
- **ほかのプラグイン:** 自分のジョブのクラスを持つプラグインは、`init.rb` で `RedmineServerlessSqsBoot.allow_job('クラス名')` を呼び、実行してよいクラスに足します。どのメールのエラーをやり直すかは [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。最後に失敗したメールは、ほかのジョブと同じくここに記録します。[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/) をインストールすると、「ジョブ」の画面は、その「Serverless」の画面のタブになり、SQS の確認は、その接続の確認に加わります。
- **Serverless では:** これまでイメージが設定していた、`config/additional_environment.rb` のキューのアダプターと、`config/aws_active_job_sqs.yml` のキューと実行してよいジョブのクラスを、プラグインが引き継ぎます([Serverless の lambda.md](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs))。
- **コードの分け方:** `boot/redmine_serverless_sqs.rb` が、キューのアダプターと gem の設定を受け持ちます。プラグインは gem でもあるので、Bundler が Rails の初期化より前に読み込みます([setup.md](setup.md#installation))。ほかは Redmine が読み込む `lib/redmine_serverless_sqs/`、`app/`、`db/` にあり、`init.rb` が有効にします。
- **migration:** 失敗の記録の表(`serverless_job_failures`)を足します。デプロイでは、`redmine:plugins:migrate` も実行します。

<a id="sponsors"></a>

## スポンサー

<Sponsors><a href="https://www.keyselect.co.jp/">KEY SELECT</a> <a href="https://localstack.cloud">LocalStack</a></Sponsors>

<a id="license"></a>

## ライセンス

Redmine Serverless SQS は、GNU General Public License バージョン 2 またはそれ以降のバージョンで公開しています。[LICENSE](../../LICENSE) を参照してください。Redmine の非公式のプラグインです。
