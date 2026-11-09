# 準備

Redmine Serverless SQS を使う Redmine に要るもの(インストール、設定、前提にする AWS のリソース、IAM の権限、ネットワーク)です。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これらをすべて CloudFormation で作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。

<a id="requirements"></a>

## 前提

- Redmine 7.0 以降。
- AWS の gem `aws-activejob-sqs` 1.2 以降(gem の依存です。チェックアウトでは、プラグインの `Gemfile` が足します)。
- ジョブを動かすもの。AWS Lambda では、SQS のイベントソースと、ハンドラー `Aws::ActiveJob::SQS::LambdaHandler.job_handler` を持つ関数。Lambda 以外では、gem の取り出し役(`aws_active_job_sqs`)。

<a id="installation"></a>

## インストール

1. プラグインを、Redmine 7.0 の `plugins/redmine_serverless_sqs` に置きます。下の gem か、このリポジトリのチェックアウトです。
2. プラグインを gem として `Gemfile.local` に足し、`bundle install` を実行します。こうすると、Bundler が、Rails の初期化より前に `boot/redmine_serverless_sqs.rb` を読み込みます。キューのアダプターは、そのときまでに設定する必要があり、Redmine がプラグインを読み込む(`init.rb`)のでは遅すぎるからです。チェックアウトなら、パスで足します。

   ```ruby
   # Redmine の Gemfile.local
   gem 'redmine_serverless_sqs', path: 'plugins/redmine_serverless_sqs'
   ```

3. `bin/rake redmine:plugins:migrate` を実行します。失敗の記録の表(`serverless_job_failures`)を作ります。
4. ほかの場所で `aws-activejob-sqs` を設定していれば、外します。`config/additional_environment.rb` のキューのアダプターと、`config/aws_active_job_sqs.yml` です。どちらもプラグインが設定します。

<a id="gem"></a>

### gem

バージョンのタグ(`v*`)ごとに、プラグインを gem として GitHub Packages(`https://rubygems.pkg.github.com/redmine-kit`)に公開します(`.github/workflows/gem.yml`)。gem は、動かすためのファイル(`init.rb`、`boot/`、`lib/`、`app/`、`config/`、`db/`、`LICENSE`)を持ちます。プラグインの `Gemfile` は入れません。Redmine は `plugins/` のプラグインだけを読み込むので、インストールした gem をそこにリンクします。

```ruby
# Redmine の Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_serverless_sqs'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <ユーザー>:<トークン>   # か、変数 BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_serverless_sqs)" plugins/redmine_serverless_sqs
```

- **アクセス:** GitHub Packages からインストールするには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。ほかのリポジトリのワークフローは、パッケージの設定(「Manage Actions access」)でそのリポジトリに Read を与えると、自分の `GITHUB_TOKEN`(`packages: read`)で読めます。

<a id="configuration"></a>

## 設定

| 設定 | 場所 | 中身 |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | すべてのプロセス(web、ジョブ、rake)の環境変数 | ジョブのキューの URL。これでプラグインが有効になる。起動のときに読む |
| キュー | プラグインが設定する | Redmine のキュー `default` と `mailers` を、どちらもジョブのキューに向ける |
| 実行してよいジョブのクラス | プラグインが設定する | `Mailer::DeliveryJob`(すべてのメール)、`DestroyProjectJob`、`DestroyProjectsJob`、`WebhookJob` と、ほかのプラグインが `RedmineServerlessSqsBoot.allow_job` で足すクラス。ほかのクラスのメッセージは実行しない(gem の `job_class_allowlist`) |
| デッドレターキュー | ジョブのキューの redrive policy | プラグインは、デッドレターキューと `maxReceiveCount` を、ここから読む(`GetQueueAttributes`)。専用の設定はない |

- **メッセージの削除:** gem は、ジョブが成功したらメッセージを消します。Lambda では、イベントの ARN からキューの URL(`https://sqs.<region>.amazonaws.com/...`)を作るので、関数がこのアドレスに届く必要があります(2026-11-09 に Serverless のイメージのテストで確認)。
- **gem のほかの設定:** プラグインが設定しないもの(たとえば、取り出し役の `visibility_timeout` や `max_messages`)は、gem の環境変数(`AWS_ACTIVE_JOB_SQS_*`)で指定できます。

<a id="aws-resources"></a>

## AWS のリソース

| リソース | 設定 |
| --- | --- |
| SQS のジョブのキュー | 標準のキュー(送り直しは FIFO のキューに対応しない)。可視性タイムアウトは、ジョブにかかりうる時間より長く(Lambda では、関数のタイムアウトの 6 倍)。3 回受け取ったらデッドレターキューに移す redrive policy。SQS が管理する鍵でのサーバー側の暗号化 |
| SQS のデッドレターキュー | 3 回失敗したジョブを受け取る。「ジョブ」の画面が `StartMessageMoveTask` で戻す |
| ジョブを動かすもの | Lambda では、ジョブのキューに SQS のイベントソースマッピングを持つ関数で、バッチの大きさは 1(ハンドラーは最初に失敗したジョブで止まり、プラグインは、呼び出しの 1 つのメッセージの失敗を記録する)。Lambda 以外では、gem の取り出し役を動かすプロセス |

<a id="iam-permissions"></a>

## IAM の権限

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| 行き先 | API | インターネットに出られない VPC の中では |
| --- | --- | --- |
| SQS | `SendMessage`、`ReceiveMessage`、`DeleteMessage`、`GetQueueAttributes`、`GetQueueUrl`、`StartMessageMoveTask` | インターフェースのエンドポイント `com.amazonaws.<region>.sqs`。`sqs.<region>.amazonaws.com` がそれを指すように、プライベートの DNS を有効にする |

<a id="tests"></a>

## テスト

テストは `test/` にあり、Redmine の標準のしくみで、Docker の中の Redmine 7.0.3、PostgreSQL 16、moto で動かします。単体と機能のテストは、SDK の応答のスタブを使います。統合のテストは moto で動かし、メールのジョブがアダプターで SQS に入り、Lambda が呼ぶハンドラーで動くこと、実行してよいクラスにないものが動かないこと、記録したジョブを送り直すと動くことを確認します。`bin/test` は、プラグインのテストのあと、ジョブのまわりの Redmine 本体のテスト(メール、プロジェクト、Webhook、管理)を動かします。`bin/test --redmine` は、プラグインを入れた状態で Redmine 本体のすべてのテストを動かします。CI はこちらです。Serverless のイメージのテストも、SQS のイベントからジョブを動かします([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#jobs-redmine_serverless_sqs))。

プラグインのテストは、プラグイン自身のファイルのカバレッジ(SimpleCov。Cobertura の XML の `coverage/coverage.xml`)も書きます。CI は、それを [Codecov](https://codecov.io/gh/redmine-kit/redmine_serverless_sqs) に送ります。

```sh
bin/test            # プラグインのテストと、ジョブのまわりの Redmine のテスト
bin/test --redmine  # Redmine のすべてのテストも
bin/lint            # RuboCop
bin/services --down # PostgreSQL と moto を止める
```

<a id="to-verify"></a>

## 確認すること

- 実際のキューでの、失敗の記録とデッドレターキューの戻し(テストは moto を使う)
- gem の取り出し役をプロセスとして動かしたときの、取り出し役のハンドラー(テストはハンドラーを呼ぶ)
