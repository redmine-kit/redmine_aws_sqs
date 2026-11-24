# 管理画面

Redmine Kit AWS SQS の管理画面です。開けるのはシステム管理者だけです (`require_admin`)。画面は、[Redmine Kit AWS](https://redmine-kit.github.io/redmine_aws/ja/admin.html#the-aws-menu) が追加し、すべての Redmine Kit AWS のプラグインが共有する Redmine の管理メニューの「AWS」の下の、「ジョブ」のタブになります。SQS の確認は、その「ステータス」のタブの接続テストにも加わります。

| 項目 | 内容 |
| --- | --- |
| 秘密を出さない | AWS の認証情報、失敗したジョブのメッセージの本文、エラーのメッセージは出しません。エラーは、Redmine Kit AWS の「ステータス」のタブと同じく、クラスで示します |
| ログのジョブの引数 | ジョブキューを使うとき、ジョブの引数は、パラメーター名 (ジョブの `perform`、メールならメーラーのメソッド) とともに Redmine のログに書きます。Redmine のレコードは ID (GlobalID) で書き、値は 50 文字で切ります。秘密の値は、Rails のパラメーターフィルター (`config.filter_parameters`。Redmine は `password`、`salt`、`twofa_totp_key`、`key` を指定) が `[FILTERED]` に置き換えます。`password` は、その指定がなくても置き換えます。アカウント情報のメールは `Mailer#account_information(user: gid://redmine-app/User/2, password: [FILTERED])` と書きます。名前がわからない引数は、レコードと数値のほかは置き換えます。対象は、ActiveJob の「Enqueued」と「Performing」の行、プラグインが記録する失敗、失敗した再送信です。Lambda では、gem のハンドラーがイベント全体を書く行を、イベントなしで書きます |
| 操作を記録する | 再送信、削除、DLQ 再処理、キューの件数の更新は、誰が何をしたかを、Redmine のログに書きます (`[redmine_kit_aws_sqs] <ログイン> resent 1 of 1 job(s)`) |

<a id="jobs"></a>

## ジョブ

![「ジョブ」のタブ。デッドレターキューに 2 件あるキューの件数と、最終的に失敗した 2 つのジョブ](./images/jobs.png)

| 項目 | 内容 | 出どころ |
| --- | --- | --- |
| キュー | 利用可能なメッセージ、処理中のメッセージ、遅延メッセージ (SQS のコンソールの語。下の「用語」)。最後の更新で読んだ値を、その日時 (「更新」) とともに表示する。画面自体は SQS を呼ばない。「最新の情報に更新」(POST) か下のタスクが件数を読み直し、プラグインのテーブル (`aws_sqs_snapshots`。最新のものだけ) に保存する。更新に失敗すると、エラーのクラスを保存し、画面に表示する。最初の更新の前は「表示するデータがありません」と表示する | SQS の `GetQueueAttributes` (`ApproximateNumberOfMessages` など) |
| デッドレターキュー | デッドレターキューにあるジョブの数 | デッドレターキューの `GetQueueAttributes`。デッドレターキューは、ジョブキューの再処理ポリシーから知る |
| 失敗したジョブの一覧 | ジョブ (メールなら、`Mailer#issue_add` のようなメーラーとメール。失敗したメールだけを並べることもできる)、エラーのクラス (メッセージは Redmine のログ)、試行回数、登録日時と失敗日時。新しい 100 件。見出し行のチェックボックスで、Redmine のチケットの一覧と同じく全行を選べる | プラグインのテーブル (下記) |
| 再送信 | 選んだジョブをジョブキューに戻し、その記録を消す | 記録したメッセージでの `SendMessage` |
| 削除 | 選んだ記録を消す | — |
| DLQ 再処理を開始 | デッドレターキューのジョブを、ジョブキューに戻す。デッドレターキューにジョブがあるときに出す | SQS の `StartMessageMoveTask` |
| 接続テスト | SQS に届くか (Redmine Kit AWS の「ステータス」のタブで) | SQS の `GetQueueAttributes` |

| 項目 | 内容 |
| --- | --- |
| 失敗の記録 | 例外を発生させたジョブは、SQS が再試行します。プラグインは、SQS がメッセージをデッドレターキューに移す前の最後の受信 (メッセージの `ApproximateReceiveCount` が、ジョブキューの再処理ポリシーの `maxReceiveCount` に届いたとき) で記録します。メッセージの本文 (`job.serialize`)、エラーのクラス、受信回数を、プラグインのテーブル (`aws_sqs_job_failures`) に保存し、ジョブ (引数は上のとおりに置き換え)、エラーのクラスとメッセージを Redmine のログに書きます (`[redmine_kit_aws_sqs] job failed after 3 receive(s): …`。JSON でない本文では、パーサーのメッセージが本文を引用するため、クラスだけ)。データベースへの書き込みが失敗したときに備えて、メッセージはそのままデッドレターキューに移ります。決して実行できないメッセージ (JSON でないもの、実行してよいクラスにないもの) は、すぐに記録して消し、再試行しません。再処理ポリシーがなければ、SQS は失敗するメッセージを保持期間が終わるまで残し、何も記録しません |
| 記録する場所 | Lambda では、プラグインが gem のハンドラー (`Aws::ActiveJob::SQS::LambdaHandler.job_handler`) を `prepend` でラップします。gem のポーラーでは、gem の `poller_error_handler` と `permanent_failure_handler` を設定します。アプリケーションが自分で設定していれば、それを使います |
| 再送信 | 記録したメッセージの本文を、アダプターが書くメッセージ属性といっしょに、そのままジョブキューに送ります。送るのは、実行してよいクラスのジョブだけです。ジョブは同じジョブ ID でもう一度動きます。記録とデッドレターキューは別々です。再送信したジョブは、たいていデッドレターキューにも残っているので、再送信するのはどちらか一方からにします (DLQ 再処理もすると、2 回動きます)。記録は、送信と同じトランザクションでロックして消すので、2 つの画面から同時に再送信しても 1 回だけ送ります。送信に失敗すると記録は残ります |
| ワーカーの設定 | Redmine は、システム管理者が変えた設定を、Web リクエストの始めにだけ読み直します。ジョブキューを使うときは、Lambda でも gem のポーラーでも、ジョブごとに最初に同じことをするので (`Setting.check_cache`。`before_perform` のコールバック)、動き続けるプロセスも今の設定でメールを送ります |
| 再送信の流れ | 先に原因を直してから (SES の送信を再開する、サプレッションリストからアドレスを外す、など)、再送信します。どのメールのエラーを再試行するかは [Redmine Kit AWS SES](https://redmine-kit.github.io/redmine_aws_ses/ja/) が決めます。メールの再送信は [Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails) にあります |
| 件数の更新 | `redmine_kit:aws:sqs:refresh` が、「最新の情報に更新」と同じくキューの件数を読みます。`REDMINE_SQS_QUEUE_URL` がないときと、SQS を読めないとき (エラーはログにあります) は、スケジュールで気付けるように失敗します (コマンドは下記)。画面を開かずに件数を新しく保つには、スケジュールで実行します |
| 記録の保持 | 次のタスクが、`DAYS` で指定した日数より前に失敗したジョブの記録を削除します (デフォルトは 90。1 から 99999 までの整数。コマンドは下記)。日数の指定は、Redmine の `redmine:users:prune` と同じ形です。Serverless は毎日実行します ([Serverless の security.md](https://redmine-kit.github.io/serverless/ja/security.html#retention-periods)) |

```sh
bin/rake redmine_kit:aws:sqs:refresh
bin/rake redmine_kit:aws:sqs:prune DAYS=90
```

| 項目 | 内容 |
| --- | --- |
| 宛先 | 一覧には、失敗したメールの宛先を出しません。メールのジョブは、ユーザーをアドレスではなく、レコードへの参照として持つからです |
| 記録の内容 | 記録はメッセージの本文を持ち、本文には、アダプターがシリアライズしたジョブの引数があります。引数の多くは Redmine のレコードを ID で指しますが、アカウント情報のメール (`Mailer#account_information`。システム管理者が「アカウント情報をユーザーに送信」にチェックしてユーザーを保存したときに送る) は、ユーザーのパスワードを持ちます。ログで置き換える引数 (上記) のある本文は、暗号化して保存し (`ActiveSupport::MessageEncryptor`。鍵は Redmine の `secret_key_base` から作る)、テーブルにパスワードの平文は残りません。再送信のときに復号します。`secret_key_base` を変えると、そうした記録は再送信できなくなります。再送信すると「ジョブのデータを復号できないため、再送信できませんでした」とエラーのクラスを表示し、選んだほかの記録は送ります。Redmine Kit AWS SES が記録する、送信しなかったメールも同じです。画面には本文を出しません。要らなくなった記録は削除し、Serverless の外でも上のタスクをスケジュールで実行します |
| ジョブキューがないとき | `REDMINE_SQS_QUEUE_URL` がなければ、画面は、Redmine が標準のとおりにジョブを動かすことを示し、残っている記録を出します。再送信はできません |

<a id="in-the-new-ui"></a>

### 新しい UI

[Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) をインストールしていれば、「ジョブ」タブは、Redmine Kit AWS のページ「AWS」のタブとして、新しい UI が描画します (`config/kit_ui.yml`。`frontend/` から `assets/javascripts/kit/sqs.js` にビルドするコンポーネント `AwsSqsJobs`。[Redmine Kit AWS の api.md](https://redmine-kit.github.io/redmine_aws/ja/api.html#the-new-ui))。`require_admin` 付きの同じアクションが Redmine の画面と JSON の両方に応答し、同じ値を表示して、同じ操作ができます。

| 部分 | 新しい UI |
| --- | --- |
| キュー | カードの見出しに「更新: …」と「最新の情報に更新」。最後の更新で保存した数と、デッドレターキューにメッセージがあれば項目の見出しに「DLQ 再処理を開始」(「DLQ 再処理を開始しますか？」の確認のあとに実行)。最後の更新のエラーは、数の代わりに表示します |
| 失敗したジョブ | 項目の見出しに「すべて」と「メール」。ジョブキューがないときは、失敗したジョブの記録があるときだけ表示します (理由は上の警告が伝えます)。チェックの列のある表。行をチェックすると、その数と「再送信」(ジョブキューがなければ無効) と「削除」。どちらも、操作と対象のジョブを示す確認 (「選択したジョブ 2 件を再送信しますか？」、「選択したジョブ 2 件を削除しますか？」と 2 行目の「記録は元に戻せず、そのジョブは再送信できなくなります。」) のあとに実行します |
| 結果 | 操作の通知、またはエラー (再送信では、失敗した記録ごと) を、項目の上に表示します |

JSON はブラウザーのセッション (kit リクエスト) で使います。`GET /admin/aws/jobs.json` (メールだけは `?mail=1`) は、Redmine のヘルパーで整形した `enabled`、`updated`、`counts` (画面の行)、`counts_error`、`dead_letter`、`failures` (`id`、`summary`、`error`、`attempts`、`enqueued_at`、`failed_at`) を返します。`POST …/resend.json` と `…/destroy.json` (`ids`)、`…/refresh.json`、`…/redrive.json` は `{ notice, errors }` を返し、SQS が拒否した再処理は 422 です。

<a id="permissions"></a>

## 権限

Web リクエストを処理するロールに、キューの件数を読み、ジョブを再送信、DLQ 再処理を開始する権限を与えます。一覧と例のポリシーは [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面の機能テストです。SDK の応答のスタブで動かします ([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。

このページの画面のスクリーンショットは、`bin/screenshots` で撮ります (Apple container が動いていれば Apple container、そうでなければ Docker の中のヘッドレス Chromium と、Redmine のテストデータ、キューの件数の例を使います)。画面を変えたら実行します。

<a id="terms"></a>

## 用語

画面の語は、SQS のコンソールとドキュメントの日本語に合わせています (2026-11-10 に確認)。

| 画面 (ja / en) | AWS の語 | 出典 | 状態 |
| --- | --- | --- | --- |
| 利用可能なメッセージ / Messages available | `ApproximateNumberOfMessagesVisible` | 第三者の記事が引く SQS のコンソールのキューの一覧 (https://dev.classmethod.jp/articles/tsnote-sqs-console-poll-messages-dlq-receive-count/)。ドキュメントの説明は「取得および処理が可能なメッセージ」(https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html) | コンソールで要確認 |
| 処理中のメッセージ / Messages in flight | `ApproximateNumberOfMessagesNotVisible` | 同じ記事。ドキュメントは「処理中メッセージ」 | コンソールで要確認 |
| 遅延メッセージ / Messages delayed | `ApproximateNumberOfMessagesDelayed` | https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-available-cloudwatch-metrics.html | ドキュメント |
| DLQ 再処理を開始 / Start DLQ redrive | `StartMessageMoveTask` | コンソールのボタン「DLQ 再処理の開始」(https://docs.aws.amazon.com/ja_jp/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-configure-dead-letter-queue-redrive.html) | ドキュメント |
