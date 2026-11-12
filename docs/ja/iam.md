# IAM 権限

プロセスの役割ごとの、プラグインが自分で呼ぶ AWS の操作です。Lambda そのものの権限 (ログ、VPC の中での実行) は入れていません。ロールの全体は [Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html) にあります。

<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `sqs:SendMessage` | ジョブキュー | ジョブを登録するすべてのプロセス (Web リクエスト、ジョブ、rake) と、「ジョブ」の画面からの再送信 |
| `sqs:ReceiveMessage`<br>`sqs:DeleteMessage`<br>`sqs:ChangeMessageVisibility`<br>`sqs:GetQueueAttributes` | ジョブキュー | ジョブを動かすもの。Lambda のイベントソースマッピング (関数のロールで動く) か、ポーラー。成功したメッセージは gem が消す。`GetQueueAttributes` は、ジョブが失敗したときに、最後の受信かを知るために、再処理ポリシーも読む |
| `sqs:GetQueueAttributes` | ジョブキューとデッドレターキュー | 「ジョブ」の画面のキューの件数と、「ステータス」のタブの SQS の接続テスト |
| `sqs:GetQueueUrl` | デッドレターキュー | 件数を読むための、再処理ポリシーの ARN からのデッドレターキューの URL |
| `sqs:StartMessageMoveTask`<br>`sqs:ReceiveMessage`<br>`sqs:DeleteMessage` | デッドレターキュー | 「ジョブ」の画面からの、ジョブキューへの DLQ 再処理。呼ぶ側には、ジョブキューへの `sqs:SendMessage` (上記) も要る |

ジョブキューへの送信 (`sqs:SendMessage`) は、ジョブを動かすプロセスでコードを実行できるのと同じ強さの権限です。ジョブはメッセージを信頼するからです。メールのジョブは、メッセージにあるクラスとメソッドを呼び (`ActionMailer::MailDeliveryJob`)、Redmine のジョブは、メッセージにある ID のプロジェクトを削除したり、Webhook を呼んだりします。実行してよいクラスはクラスを限るだけで、引数は限りません。ジョブキューへの `sqs:SendMessage` は、Redmine 自身のロールだけに与えます。

メッセージを戻すための権限は、DLQ 再処理を開始するための AWS の最小の権限です。デッドレターキューへの `sqs:StartMessageMoveTask`、`sqs:ReceiveMessage`、`sqs:DeleteMessage`、`sqs:GetQueueAttributes` と、戻し先への `sqs:SendMessage` です ([Amazon SQS デベロッパーガイド](https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html)。2026-11-10 に確認)。KMS のカスタマーマネージドキーを使うなら、`kms:Decrypt` と `kms:GenerateDataKey` も要ります。ここのキューは、SQS マネージドキーを使います。

<a id="example-policy"></a>

## ポリシーの例

Web リクエストを処理するロール (ジョブの登録、「ジョブ」の画面):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnqueueAndJobsPage",
      "Effect": "Allow",
      "Action": ["sqs:SendMessage", "sqs:GetQueueAttributes"],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs"
    },
    {
      "Sid": "DeadLetterQueue",
      "Effect": "Allow",
      "Action": [
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl",
        "sqs:StartMessageMoveTask",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage"
      ],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs-dlq"
    }
  ]
}
```

ジョブを動かすロール:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RunJobs",
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility",
        "sqs:GetQueueAttributes",
        "sqs:SendMessage"
      ],
      "Resource": "arn:aws:sqs:<region>:<account>:<instance>-jobs"
    }
  ]
}
```

<a id="resource-based-policies"></a>

## リソースベースのポリシー

ありません。キューは SQS マネージドキーで暗号化するので、キーポリシーは要りません。ほかのプリンシパルにジョブキューへの送信を許すキューポリシーは追加しません ([権限](#permissions))。

<a id="not-checked-yet"></a>

## 未確認の事項

- 実際のキューでの、上のポリシー (テストは AWS Emulator を使い、AWS Emulator は IAM のポリシーを評価しない)。
