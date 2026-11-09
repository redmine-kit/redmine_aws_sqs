# Redmine Serverless SQS

Redmine Serverless SQS(`redmine_serverless_sqs`)は、Redmine のバックグラウンドのジョブを Amazon SQS で動かす Redmine のプラグインです。ジョブは、AWS の公式の gem `aws-activejob-sqs` で SQS に送り、プラグインは、それを運用するのに要るもの(設定、最後に失敗したジョブの記録、送り直しの画面)を足します。[Serverless](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs) が、Lambda 用のイメージに入れて使います。Redmine 本体のファイルは書き換えません。今は設計段階で、資料だけがあります。

- [準備](setup.md): 前提、インストール、設定、AWS のリソース、ネットワーク、テスト
- [IAM の権限](iam.md): 権限、例のポリシー、リソースベースのポリシー
- [管理画面](admin.md): ジョブ

<a id="features"></a>

## 機能

機能ごとに、有効にする条件を持たせます。条件がそろわなければ、Redmine は標準のままにジョブを動かします。

| 機能 | 中身 | 有効にする条件 | 資料 |
| --- | --- | --- | --- |
| SQS でのジョブ | ActiveJob のキューのアダプターを `aws-activejob-sqs` にし、Redmine のキュー(`default`、`mailers`)をジョブのキューに向け、Redmine のジョブのクラス(`ActionMailer::MailDeliveryJob`、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob`)だけを実行させる | `REDMINE_JOBS_QUEUE_URL` がある | [setup.md](setup.md#configuration) |
| ジョブの失敗の記録 | 最後に失敗したジョブ(やり直しを使い切ったもの、やり直さないエラー)を、中身とエラーといっしょに記録し、送り直せるようにする | 同上 | [admin.md](admin.md#jobs) |
| 管理画面 | キューの件数、失敗したジョブ、送り直し、デッドレターキューの戻し | 管理者 | [admin.md](admin.md) |

- **Lambda でも、Lambda 以外でも:** キューからジョブを取り出して動かすものが要ります。AWS Lambda では、SQS のイベントソースを持つ関数が、gem の `Aws::ActiveJob::SQS::LambdaHandler` で動かします(Serverless では `redmine-worker`。ハンドラーは、プラグインではなくイメージで設定します)。Lambda 以外では、gem の取り出し役(`aws_active_job_sqs`)を、ECS や EC2 などで別のプロセスとして動かします。
- **ほかのプラグイン:** どのメールのエラーをやり直すかは [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。最後に失敗したメールは、ほかのジョブと同じくここに記録します。[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/) を入れると、「ジョブ」の画面は、その「Serverless」の画面のタブになり、SQS の確認は、その接続の確認に加わります。
- **今の Serverless:** このプラグインを書くまでは、イメージが、キューのアダプターを `config/additional_environment.rb` で、キューと実行してよいジョブのクラスを `config/aws_active_job_sqs.yml` で設定します([Serverless の lambda.md](https://redmine-kit.github.io/serverless/ja/lambda.html#background-jobs))。プラグインが、これを引き継ぎます。
- **migration:** 失敗の記録の表(`serverless_job_failures`)を足します。デプロイでは、`redmine:plugins:migrate` も実行します。
