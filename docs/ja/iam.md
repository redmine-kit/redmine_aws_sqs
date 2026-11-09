# IAM の権限

プロセスの役割ごとの、プラグインが自分で呼ぶ AWS の操作です。Lambda そのものの権限(ログ、VPC の中での実行)は入れていません。ロールの全体は [Serverless の iam.md](https://redmine-kit.github.io/serverless/ja/iam.html) にあります。

<a id="permissions"></a>

## 権限

| 操作 | 対象 | 理由 |
| --- | --- | --- |
| `sqs:SendMessage` | ジョブのキュー | ジョブを入れるすべてのプロセス(web の要求、ジョブ、rake)と、「ジョブ」の画面からの送り直し |
| `sqs:ReceiveMessage`、`sqs:DeleteMessage`、`sqs:ChangeMessageVisibility`、`sqs:GetQueueAttributes` | ジョブのキュー | ジョブを動かすもの。Lambda のイベントソースマッピング(関数のロールで動く)か、取り出し役。成功したメッセージは gem が消す |
| `sqs:GetQueueAttributes` | ジョブのキューとデッドレターキュー | 「ジョブ」の画面のキューの件数と、「状態と接続」の SQS の確認 |
| `sqs:StartMessageMoveTask`、`sqs:ListMessageMoveTasks` | デッドレターキュー | 「ジョブ」の画面から、デッドレターキューをジョブのキューに戻す |

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
      "Resource": [
        "arn:aws:sqs:<region>:<account>:<instance>-jobs",
        "arn:aws:sqs:<region>:<account>:<instance>-jobs-dlq"
      ]
    },
    {
      "Sid": "Redrive",
      "Effect": "Allow",
      "Action": ["sqs:StartMessageMoveTask", "sqs:ListMessageMoveTasks"],
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

- `StartMessageMoveTask` を呼ぶ側に、デッドレターキューへの `sqs:ReceiveMessage` と `sqs:DeleteMessage`、ジョブのキューへの `sqs:SendMessage` も要るか。
