# 管理画面

Redmine AWS SQS の管理画面です。開けるのは Redmine の管理者だけです(`require_admin`)。画面は、[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html#the-serverless-menu) をインストールしているかどうかにかかわらず、すべての Redmine Serverless のプラグインが共有する Redmine の管理のメニューの「Serverless」の下の、「ジョブ」のタブになります。Redmine Serverless をインストールしているときは、SQS の確認がその接続テストにも加わります。

| 項目 | 内容 |
| --- | --- |
| 秘密を出さない | AWS の認証情報と、失敗したジョブのメッセージの本文は出しません。キューの件数は 1 分キャッシュします |
| 操作を記録する | 再送信、削除、DLQ 再処理は、誰が何をしたかを、Redmine のログに書きます(`[redmine_aws_sqs] <ログイン> resent 1 of 1 job(s)`) |

<a id="jobs"></a>

## ジョブ

![「ジョブ」のタブ。デッドレターキューに 2 件あるキューの件数と、最後まで失敗した 2 つのジョブ](./images/jobs.png)

| 項目 | 内容 | 出どころ |
| --- | --- | --- |
| キュー | 利用可能なメッセージ、処理中のメッセージ、遅延メッセージ(SQS のコンソールの語。下の「用語」) | SQS の `GetQueueAttributes`(`ApproximateNumberOfMessages` など) |
| デッドレターキュー | デッドレターキューにあるジョブの数 | デッドレターキューの `GetQueueAttributes`。デッドレターキューは、ジョブのキューの redrive policy から知る |
| 失敗したジョブの一覧 | ジョブ(メールなら、`Mailer#issue_add` のようなメーラーとメール。失敗したメールだけを並べることもできる)、エラーのクラスとメッセージ、試行回数、登録日時と失敗日時。新しい 100 件。見出しの行のチェックボックスで、Redmine のチケットの一覧と同じく全行を選べる | プラグインの表(下記) |
| 再送信 | 選んだジョブをジョブのキューに入れ直し、その記録を消す | 記録したメッセージでの `SendMessage` |
| 削除 | 選んだ記録を消す | — |
| DLQ 再処理を開始 | デッドレターキューのジョブを、ジョブのキューに戻す。デッドレターキューにジョブがあるときに出す | SQS の `StartMessageMoveTask` |
| 接続テスト | SQS に届くか(Redmine Serverless を入れていれば、その「ステータス」のタブで) | SQS の `GetQueueAttributes` |

| 項目 | 内容 |
| --- | --- |
| 失敗の記録 | 例外を発生させたジョブは、SQS がやり直します。プラグインは、SQS がメッセージをデッドレターキューに移す前の最後の受け取り(メッセージの `ApproximateReceiveCount` が、ジョブのキューの redrive policy の `maxReceiveCount` に届いたとき)で記録します。メッセージの本文(`job.serialize`)、エラー、受け取った回数を、自分の表(`aws_sqs_job_failures`)に入れます。データベースへの書き込みが失敗したときに備えて、メッセージはそのままデッドレターキューに移ります。決して実行できないメッセージ(JSON でないもの、実行してよいクラスにないもの)は、すぐに記録して消し、やり直しません。redrive policy がなければ、SQS は失敗するメッセージを保持期間が終わるまで残し、何も記録しません |
| 記録する場所 | Lambda では、プラグインが gem のハンドラー(`Aws::ActiveJob::SQS::LambdaHandler.job_handler`)を `prepend` で包みます。gem の取り出し役では、gem の `poller_error_handler` と `permanent_failure_handler` を設定します。アプリケーションが自分で設定していれば、それを使います |
| 再送信 | 記録したメッセージの本文を、アダプターが書くメッセージの属性といっしょに、そのままジョブのキューに送ります。送るのは、実行してよいクラスのジョブだけです。ジョブは同じジョブの ID でもう一度動きます。記録とデッドレターキューは別々です。再送信したジョブは、たいていデッドレターキューにも残っているので、再送信するのはどちらか一方からにします(デッドレターキューも戻すと、2 回動きます) |
| 再送信の流れ | 先に原因を直してから(SES の送信を再開する、抑止リストからアドレスを外す、など)、再送信します。どのメールのエラーをやり直すかは [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。メールの再送信は [Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails) にあります |
| 記録の保持 | 次のタスクが、指定した日数より前に失敗したジョブの記録を消します(デフォルトは 90 日)。Serverless は毎日動かします([Serverless の security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods)) |

  ```sh
  bin/rake redmine_aws_sqs:prune_records[<日数>]
  ```
| 項目 | 内容 |
| --- | --- |
| 宛先 | 一覧には、失敗したメールの宛先を出しません。メールのジョブは、利用者をアドレスではなく、レコードへの参照として持つからです |
| ジョブのキューがないとき | `REDMINE_JOBS_QUEUE_URL` がなければ、画面は、Redmine が標準のとおりにジョブを動かすことを示し、残っている記録を出します。再送信はできません |

<a id="permissions"></a>

## 権限

web の要求のロールに、キューの件数を読み、ジョブを再送信、DLQ 再処理を開始する権限を与えます。一覧と例のポリシーは [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面の機能のテストです。SDK の応答のスタブで動かします([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。

このページの画面のスクリーンショットは、`bin/screenshots` で撮ります(Docker の中のヘッドレスの Chromium と、Redmine のテストのデータと、例のキューの件数)。画面を変えたら実行します。

<a id="terms"></a>

## 用語

画面の語は、SQS の AWS のコンソールとドキュメントの日本語に合わせています(2026-11-10 に確認)。

| 画面(ja / en) | AWS の語 | 出典 | 状態 |
| --- | --- | --- | --- |
| 利用可能なメッセージ / Messages available | `ApproximateNumberOfMessagesVisible` | 第三者の記事が引く SQS のコンソールのキューの一覧(https://dev.classmethod.jp/articles/tsnote-sqs-console-poll-messages-dlq-receive-count/)。ドキュメントの説明は「取得および処理が可能なメッセージ」(https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html) | コンソールで要確認 |
| 処理中のメッセージ / Messages in flight | `ApproximateNumberOfMessagesNotVisible` | 同じ記事。ドキュメントは「処理中メッセージ」 | コンソールで要確認 |
| 遅延メッセージ / Messages delayed | `ApproximateNumberOfMessagesDelayed` | https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html | ドキュメント |
| DLQ 再処理を開始 / Start DLQ redrive | `StartMessageMoveTask` | コンソールのボタン「DLQ 再処理の開始」(https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html) | ドキュメント |
