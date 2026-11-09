# 管理画面

Redmine Serverless SQS の管理画面の設計です。開けるのは Redmine の管理者だけです(`require_admin`)。画面は、[Redmine Serverless](https://redmine-kit.github.io/redmine_serverless/ja/admin.html#the-serverless-menu) をインストールしているかどうかにかかわらず、すべての Redmine Serverless のプラグインが共有する Redmine の管理のメニューの「Serverless」の下の、「ジョブ」のタブになります。Redmine Serverless をインストールしているときは、SQS の確認がその接続の確認にも加わります。

- **秘密を出さない:** AWS の認証情報は出しません。キューの件数は 1 分キャッシュします。
- **操作を記録する:** 送り直しと削除は、誰がいつ何をしたかを、Redmine のログに書きます。

<a id="jobs"></a>

## ジョブ

| 項目 | 中身 | 出どころ |
| --- | --- | --- |
| キューの件数 | 待っているジョブ、動いているジョブ、遅らせたジョブ | SQS の `GetQueueAttributes`(`ApproximateNumberOfMessages` など) |
| デッドレターキューの件数 | やり直しを使い切ったジョブの数 | 同上 |
| 失敗したジョブの一覧 | ジョブの種類(メールなら、メールの種類と宛先。失敗したメールだけを並べることもできる)、エラーの種類とメッセージ、試した回数、最初と最後の時刻 | プラグインの表(下記) |
| 送り直し | 1 件ずつ、または選んだものをまとめて、SQS に入れ直す | 記録したジョブの中身から入れ直す |
| 削除 | 送り直さない失敗を一覧から消す | — |
| デッドレターキューの戻し | デッドレターキューのジョブを、元のキューに戻す | SQS の `StartMessageMoveTask` |
| 接続の確認 | SQS に届くか(Redmine Serverless を入れていれば、その「状態と接続」で) | SQS の `GetQueueAttributes` |

- **失敗の記録:** ジョブが最後に失敗したとき(やり直しを使い切ったとき、やり直さないエラーのとき)、プラグインは、ジョブの中身(`job.serialize`)とエラーを、自分の表(`serverless_job_failures`)に入れます。データベースへの書き込みが失敗したときに備えて、デッドレターキューも残します。
- **送り直しの流れ:** 先に原因を直してから(SES の送信を再開する、抑止リストからアドレスを外す、など)、送り直しのボタンを押します。どのメールのエラーをやり直すかは [Redmine Serverless SES](https://redmine-kit.github.io/redmine_serverless_ses/ja/) が決めます。メールの送り直しは [Serverless の mail.md](https://redmine-kit.github.io/serverless/ja/mail.html#when-sending-fails) にあります。

<a id="permissions"></a>

## 権限

web の要求のロールに、キューの件数を読み、ジョブを送り直し、デッドレターキューを戻す権限を与えます。一覧と例のポリシーは [iam.md](iam.md) にあります。

<a id="tests"></a>

## テスト

画面の機能のテストとシステムのテストです([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#administration-pages))。
