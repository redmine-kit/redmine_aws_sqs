# IAM の権限

プロセスの役割ごとの、プラグインが自分で呼ぶ AWS の操作です。Lambda そのものの権限(ログ、VPC の中での実行)は入れていません。ロールの全体は [Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html) にあります。

<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `sqs:SendMessage` | ジョブのキュー | ジョブを入れるすべてのプロセス(web の要求、ジョブ、rake)と、「ジョブ」の画面からの送り直し |
| `sqs:ReceiveMessage`、`sqs:DeleteMessage`、`sqs:ChangeMessageVisibility`、`sqs:GetQueueAttributes` | ジョブのキュー | ジョブを動かすもの。Lambda のイベントソースマッピング(関数のロールで動く)か、取り出し役。成功したメッセージは gem が消す。`GetQueueAttributes` は、ジョブが失敗したときに、最後の受け取りかを知るために、redrive policy も読む |
| `sqs:GetQueueAttributes` | ジョブのキューとデッドレターキュー | 「ジョブ」の画面のキューの件数と、「状態と接続」の SQS の確認 |
| `sqs:GetQueueUrl` | デッドレターキュー | 件数を読むための、redrive policy の ARN からのデッドレターキューの URL |
| `sqs:StartMessageMoveTask`、`sqs:ReceiveMessage`、`sqs:DeleteMessage` | デッドレターキュー | 「ジョブ」の画面から、デッドレターキューをジョブのキューに戻す。呼ぶ側には、ジョブのキューへの `sqs:SendMessage`(上記)も要る |

- **戻すための権限:** デッドレターキューの戻しを始めるための、AWS の最小の権限です。デッドレターキューへの `sqs:StartMessageMoveTask`、`sqs:ReceiveMessage`、`sqs:DeleteMessage`、`sqs:GetQueueAttributes` と、戻し先への `sqs:SendMessage` です([Amazon SQS デベロッパーガイド](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html)。2026-11-10 に確認)。カスタマー管理の KMS の鍵では、`kms:Decrypt` と `kms:GenerateDataKey` も要ります。ここのキューは、SQS が管理する鍵を使います。

<a id="example-policy"></a>

## 例のポリシー

web の要求のロール(ジョブを入れる、「ジョブ」の画面):

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

ありません。キューは SQS が管理する鍵で暗号化するので、鍵のポリシーは要りません。

<a id="not-checked-yet"></a>

## 未確認のこと

- 実際のキューでの、上のポリシー(テストは moto を使い、moto は IAM を確認しない)。
