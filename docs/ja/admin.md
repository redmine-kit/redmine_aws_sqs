# 管理画面

Redmine Serverless SQS の管理画面です。開けるのは Redmine の管理者だけです(`require_admin`)。画面は、[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html#the-serverless-menu) をインストールしているかどうかにかかわらず、すべての Redmine Serverless のプラグインが共有する Redmine の管理のメニューの「Serverless」の下の、「ジョブ」のタブになります。Redmine Serverless をインストールしているときは、SQS の確認がその接続の確認にも加わります。

| 項目 | 内容 |
| --- | --- |
| 秘密を出さない | AWS の認証情報と、失敗したジョブのメッセージの本文は出しません。キューの件数は 1 分キャッシュします |
| 操作を記録する | 送り直し、削除、デッドレターキューの戻しは、誰が何をしたかを、Redmine のログに書きます(`[redmine_serverless_sqs] <ログイン> resent 1 of 1 job(s)`) |

<a id="jobs"></a>

## ジョブ

![「ジョブ」のタブ。デッドレターキューに 2 件あるキューの件数と、最後まで失敗した 2 つのジョブ](./images/jobs.png)

| 項目 | 内容 | 出どころ |
| --- | --- | --- |
| キューの件数 | 待っているジョブ、動いているジョブ、遅らせたジョブ | SQS の `GetQueueAttributes`(`ApproximateNumberOfMessages` など) |
| デッドレターキューの件数 | デッドレターキューにあるジョブの数 | デッドレターキューの `GetQueueAttributes`。デッドレターキューは、ジョブのキューの redrive policy から知る |
| 失敗したジョブの一覧 | ジョブ(メールなら、`Mailer#issue_add` のようなメーラーとメール。失敗したメールだけを並べることもできる)、エラーのクラスとメッセージ、受け取った回数、キューに入れた日時と失敗した日時。新しい 100 件 | プラグインの表(下記) |
| 送り直し | 選んだジョブをジョブのキューに入れ直し、その記録を消す | 記録したメッセージでの `SendMessage` |
| 削除 | 選んだ記録を消す | — |
| デッドレターキューの戻し | デッドレターキューのジョブを、ジョブのキューに戻す。デッドレターキューにジョブがあるときに出す | SQS の `StartMessageMoveTask` |
| 接続の確認 | SQS に届くか(Redmine Serverless を入れていれば、その「状態と接続」で) | SQS の `GetQueueAttributes` |

| 項目 | 内容 |
| --- | --- |
| 失敗の記録 | 例外を発生させたジョブは、SQS がやり直します。プラグインは、SQS がメッセージをデッドレターキューに移す前の最後の受け取り(メッセージの `ApproximateReceiveCount` が、ジョブのキューの redrive policy の `maxReceiveCount` に届いたとき)で記録します。メッセージの本文(`job.serialize`)、エラー、受け取った回数を、自分の表(`serverless_job_failures`)に入れます。データベースへの書き込みが失敗したときに備えて、メッセージはそのままデッドレターキューに移ります。決して実行できないメッセージ(JSON でないもの、実行してよいクラスにないもの)は、すぐに記録して消し、やり直しません。redrive policy がなければ、SQS は失敗するメッセージを保持期間が終わるまで残し、何も記録しません |
| 記録する場所 | Lambda では、プラグインが gem のハンドラー(`Aws::ActiveJob::SQS::LambdaHandler.job_handler`)を `prepend` で包みます。gem の取り出し役では、gem の `poller_error_handler` と `permanent_failure_handler` を設定します。アプリケーションが自分で設定していれば、それを使います |
| 送り直し | 記録したメッセージの本文を、アダプターが書くメッセージの属性といっしょに、そのままジョブのキューに送ります。送るのは、実行してよいクラスのジョブだけです。ジョブは同じジョブの ID でもう一度動きます。記録とデッドレターキューは別々です。送り直したジョブは、たいていデッドレターキューにも残っているので、送り直すのはどちらか一方からにします(デッドレターキューも戻すと、2 回動きます) |
| 送り直しの流れ | 先に原因を直してから(SES の送信を再開する、抑止リストからアドレスを外す、など)、送り直します。どのメールのエラーをやり直すかは [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。メールの送り直しは [Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails) にあります |
| 記録の保持 | 次のタスクが、指定した日数より前に失敗したジョブの記録を消します(既定は 90 日)。Serverless は毎日動かします([Serverless の security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods)) |

  ```sh
  bin/rake redmine_serverless_sqs:prune_records[<日数>]
  ```
| 項目 | 内容 |
| --- | --- |
| 宛先 | 一覧には、失敗したメールの宛先を出しません。メールのジョブは、利用者をアドレスではなく、レコードへの参照として持つからです |
| ジョブのキューがないとき | `REDMINE_JOBS_QUEUE_URL` がなければ、画面は、Redmine が標準のとおりにジョブを動かすことを示し、残っている記録を出します。送り直しはできません |

<a id="permissions"></a>

## 権限

web の要求のロールに、キューの件数を読み、ジョブを送り直し、デッドレターキューを戻す権限を与えます。一覧と例のポリシーは [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面の機能のテストです。SDK の応答のスタブで動かします([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。

このページの画面のスクリーンショットは、`bin/screenshots` で撮ります(Docker の中のヘッドレスの Chromium と、Redmine のテストのデータと、例のキューの件数)。画面を変えたら実行します。
