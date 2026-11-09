# 準備

Redmine Serverless SQS を使う Redmine に要るもの(インストール、設定、前提にする AWS のリソース、IAM の権限、ネットワーク)です。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これらをすべて CloudFormation で作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。プラグインは設計段階なので、下の内容は設計で、コードを書くときに確認します。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の gem `aws-activejob-sqs`(1.2 以降。プラグインの `Gemfile` が足します)。
- ジョブを動かすもの。AWS Lambda では、SQS のイベントソースと、ハンドラー `Aws::ActiveJob::SQS::LambdaHandler.job_handler` を持つ関数。Lambda 以外では、gem の取り出し役(`aws_active_job_sqs`)。

<a id="installation"></a>

## インストール

1. プラグインを `plugins/redmine_serverless_sqs` に置き、`bundle install` を実行します(プラグインの `Gemfile` は、Redmine の `Gemfile` が読み込みます)。
2. `bin/rake redmine:plugins:migrate` を実行します。失敗の記録の表(`serverless_job_failures`)を作ります。

<a id="configuration"></a>

## 設定

| 設定 | 場所 | 中身 |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | すべてのプロセス(web、ジョブ、rake)の環境変数 | ジョブのキューの URL。これでプラグインが有効になる |
| キュー | プラグインが設定する | Redmine のキュー `default` と `mailers` を、どちらもジョブのキューに向ける |
| 実行してよいジョブのクラス | プラグインが設定する | `ActionMailer::MailDeliveryJob`、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob`。ほかのクラスのメッセージは実行しない(gem の `job_class_allowlist`) |

- **メッセージの削除:** gem は、ジョブが成功したらメッセージを消します。Lambda では、イベントの ARN からキューの URL(`https://sqs.<region>.amazonaws.com/...`)を作るので、関数がこのアドレスに届く必要があります(2026-11-09 に Serverless のイメージのテストで確認)。
- **デッドレターキュー:** 「ジョブ」の画面のために、プラグインがデッドレターキューをどう知るか(専用の設定か、ジョブのキューの redrive policy か)は、コードを書くときに決めます(未決定)。

<a id="aws-resources"></a>

## AWS のリソース

| リソース | 設定 |
| --- | --- |
| SQS のジョブのキュー | 標準のキュー。可視性タイムアウトは、ジョブにかかりうる時間より長く(Lambda では、関数のタイムアウトの 6 倍)。3 回受け取ったらデッドレターキューに移す redrive policy。SQS が管理する鍵でのサーバー側の暗号化 |
| SQS のデッドレターキュー | 3 回失敗したジョブを受け取る。「ジョブ」の画面が `StartMessageMoveTask` で戻す |
| ジョブを動かすもの | Lambda では、ジョブのキューに SQS のイベントソースマッピングを持つ関数(バッチの大きさは 1)。Lambda 以外では、gem の取り出し役を動かすプロセス |

<a id="iam-permissions"></a>

## IAM の権限

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| 行き先 | API | インターネットに出られない VPC の中では |
| --- | --- | --- |
| SQS | `SendMessage`、`ReceiveMessage`、`DeleteMessage`、`GetQueueAttributes`、`StartMessageMoveTask` | インターフェースのエンドポイント `com.amazonaws.<region>.sqs`。`sqs.<region>.amazonaws.com` がそれを指すように、プライベートの DNS を有効にする |

<a id="tests"></a>

## テスト

Redmine の標準のプラグインのテストです(`bin/rake redmine:plugins:test NAME=redmine_serverless_sqs`)。SQS は moto で再現します。Serverless のイメージのテストは、SQS のイベントからジョブを動かし、許可の一覧にないクラスが実行されないことを確認します([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html))。

<a id="to-verify"></a>

## 確認すること

- やり直しを使い切ったときと、やり直さないエラーのときに、Rails の ActiveJob のどの仕組みで失敗を記録するか(`after_discard` など)
- プラグインが、デッドレターキューをどう知るか
