# 導入

Redmine AWS SQS を使う Redmine に要るもの (インストール、設定、前提とする AWS リソース、IAM 権限、ネットワーク) です。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これらをすべて CloudFormation で作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。

<a id="requirements"></a>

## 動作環境

- Redmine 7.0 以降。
- `plugins/redmine_aws` の [Redmine AWS](https://redmine-kit.github.io/redmine_aws/ja/) (`redmine_aws`) 0.1 以降。これがないと Redmine は起動しません (`init.rb` の `requires_redmine_plugin`)。gem もこれに依存します。「AWS」の管理メニューを追加します。
- AWS の gem `aws-activejob-sqs` 1.2 以降 (gem の依存です。チェックアウトでは、プラグインの `Gemfile` が追加します)。
- ジョブを動かすもの。AWS Lambda では、SQS のイベントソースと、ハンドラー `Aws::ActiveJob::SQS::LambdaHandler.job_handler` を持つ関数。Lambda 以外では、gem のポーラー (`aws_active_job_sqs`)。

<a id="installation"></a>

## インストール

1. プラグインを Redmine 7.0 の `plugins/redmine_aws_sqs` に、Redmine AWS を `plugins/redmine_aws` に置きます。下の gem か、リポジトリのチェックアウトです。
2. プラグインを gem として `Gemfile.local` に追加し、インストールします。

   ```sh
   bundle install
   ```

   こうすると、Bundler が、Rails の初期化より前に `boot/redmine_aws_sqs.rb` を読み込みます。キューアダプターは、そのときまでに設定する必要があり、Redmine がプラグインを読み込む (`init.rb`) のでは遅すぎるからです。チェックアウトなら、両方をパスで追加します。Redmine AWS も書きます。プラグインの gemspec が必要とし、rubygems.org にはないためです。Bundler は読み込みません (読み込むのは Redmine です)。Redmine AWS のプラグインを複数追加するときも、`redmine_aws` は 1 回だけ書きます。Bundler は、同じ gem を 2 つのソースから取ることを拒み、重複には警告を出します。

   ```ruby
   # Redmine の Gemfile.local
   gem 'redmine_aws', path: 'plugins/redmine_aws', require: false
   gem 'redmine_aws_sqs', path: 'plugins/redmine_aws_sqs'
   ```

3. プラグインの migration を実行します。

   ```sh
   bin/rake redmine:plugins:migrate
   ```

   失敗の記録のテーブル (`aws_sqs_job_failures`) を作ります。
4. ほかの場所で `aws-activejob-sqs` を設定していれば、外します。`config/additional_environment.rb` のキューアダプターと、`config/aws_active_job_sqs.yml` です。どちらもプラグインが設定します。

<a id="gem"></a>

### gem

バージョンのタグ (`v*`) ごとに、プラグインを gem として GitHub Packages (`https://rubygems.pkg.github.com/redmine-kit`) に公開します (`.github/workflows/gem.yml`)。gem は、動かすためのファイル (`init.rb`、`boot/`、`lib/`、`app/`、`config/`、`db/`、`help/`、`LICENSE`) を持ち、`redmine_aws`、`aws-activejob-sqs`、`aws-sdk-sqs` に依存します。プラグインの `Gemfile` は入れません。Redmine AWS の gem は、Bundler が同じソースからいっしょにインストールするので、`Gemfile.local` にはプラグインだけを書きます。Redmine は `plugins/` のプラグインだけを読み込むので、インストールした gem をそこにリンクします。

```ruby
# Redmine の Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_aws_sqs'
end
```

```sh
bundle config set --global rubygems.pkg.github.com <ユーザー>:<トークン>   # か、変数 BUNDLE_RUBYGEMS__PKG__GITHUB__COM
bundle install
ln -s "$(bundle info --path redmine_aws)" plugins/redmine_aws
ln -s "$(bundle info --path redmine_aws_sqs)" plugins/redmine_aws_sqs
```

GitHub Packages からインストールするには、公開のパッケージでも、`read:packages` の権限を持つ GitHub のトークンが要ります。ほかのリポジトリのワークフローは、パッケージの設定 (「Manage Actions access」) でそのリポジトリに Read を与えると、自分の `GITHUB_TOKEN` (`packages: read`) で読めます。

<a id="configuration"></a>

## 設定

| キー | 説明 | パラメーター |
| --- | --- | --- |
| `REDMINE_JOBS_QUEUE_URL` | ジョブキューの URL。これでプラグインが有効になる。起動時に読む | 必須。すべてのプロセス (web、ジョブ、rake) に設定する |

| 項目 | 説明 | 変える場所 |
| --- | --- | --- |
| キュー | Redmine のキュー `default` と `mailers` を、どちらもジョブキューに向ける | 変えられない (プラグインが設定する) |
| 実行を許可するジョブクラス | 一覧にないクラスのメッセージは実行しない (gem の `job_class_allowlist`)。一覧は下記 | ほかのプラグインが `RedmineAws::SQS::Boot.allow_job` で追加する |
| デッドレターキュー | プラグインは、デッドレターキューと `maxReceiveCount` を、ここから読む (`GetQueueAttributes`)。専用の設定はない | ジョブキューの再処理ポリシー |

<a id="allowed-job-classes"></a>

### 実行を許可するジョブクラス

キューが実行するのは、次のジョブクラスだけです。

- `Mailer::DeliveryJob` (すべてのメール)
- `DestroyProjectJob` と `DestroyProjectsJob`
- `WebhookJob`
- ほかの Redmine AWS のプラグインのジョブ: `AwsS3ReconcileJob` と `AwsSesReimportMailJob`
- ほかのプラグインが `RedmineAws::SQS::Boot.allow_job` で追加するクラス

<a id="message-deletion"></a>

### メッセージの削除

gem は、ジョブが成功したらメッセージを消します。Lambda では、イベントの ARN からキューの URL (`https://sqs.<region>.amazonaws.com/...`) を作ります。ジョブキューについては、プラグインがその代わりに `REDMINE_JOBS_QUEUE_URL` を使います。そのため削除は、ジョブと同じエンドポイント (LocalStack や、プライベート DNS のないインターフェイスエンドポイント) に届きます。ほかのキューは、ARN から作った URL のままです。

<a id="other-settings-of-the-gem"></a>

### gem のほかの設定

プラグインが設定しないもの (たとえば、ポーラーの `visibility_timeout` や `max_messages`) は、gem の環境変数 (`AWS_ACTIVE_JOB_SQS_*`) で指定できます。

<a id="aws-resources"></a>

## AWS リソース

| リソース | 設定 |
| --- | --- |
| SQS のジョブキュー | 標準キュー (再送信は FIFO キューに対応しない)。可視性タイムアウトは、ジョブにかかりうる時間より長く (Lambda では、関数のタイムアウトの 6 倍)。3 回受信したらデッドレターキューに移す再処理ポリシー。SQS マネージドキー (SSE-SQS) によるサーバー側の暗号化 |
| SQS のデッドレターキュー | 3 回失敗したジョブを受け取る。「ジョブ」の画面が `StartMessageMoveTask` で戻す |
| ジョブを動かすもの | Lambda では、ジョブキューに SQS のイベントソースマッピングを持つ関数で、バッチサイズは 1 (ハンドラーは最初に失敗したジョブで止まり、プラグインは、呼び出しの 1 つのメッセージの失敗を記録する)。Lambda 以外では、gem のポーラーを動かすプロセス |

<a id="iam-permissions"></a>

## IAM 権限

プラグインに要る権限と例のポリシーは、[iam.md](iam.md) にあります。

<a id="network"></a>

## ネットワーク

| 接続先 | API | インターネットに出られない VPC の中では |
| --- | --- | --- |
| SQS | `SendMessage`<br>`ReceiveMessage`<br>`DeleteMessage`<br>`GetQueueAttributes`<br>`GetQueueUrl`<br>`StartMessageMoveTask` | インターフェイスエンドポイント `com.amazonaws.<region>.sqs`。`sqs.<region>.amazonaws.com` がそれを指すように、プライベート DNS を有効にする |

<a id="tests"></a>

## テスト

テストは `test/` にあり、Redmine 標準のしくみで、Docker の中の Redmine 7.0.3 と PostgreSQL 16 で動かします。AWS は、`LOCALSTACK_AUTH_TOKEN` があれば LocalStack です (CI は組織のシークレットを使う)。LocalStack が起動しなければ失敗にします。トークンがなければ (フォークからの Pull Request、手元での実行)、同じテストを moto で動かします。ログに使ったほうを出します。プラグインが呼ぶ SQS の操作は LocalStack にすべてあるので、LocalStack ではモックしません。`StartMessageMoveTask` のない moto では、そのテストだけを飛ばし、SDK の応答のスタブで確認します。単体テストと機能テストは、SDK の応答のスタブを使います。

| 対象 | 確認すること |
| --- | --- |
| SQS でのジョブ | メールのジョブが `aws-activejob-sqs` で SQS に入り、Lambda が呼ぶハンドラーで動き、メールが送られる。`REDMINE_JOBS_QUEUE_URL` がなければ、Redmine は標準のとおりにジョブを動かす |
| 許可の一覧 | 実行してよいクラスにないメッセージは動かさず、記録して消す |
| 失敗の記録 | 最後の受信 (再処理ポリシーから) で記録し、その前と、再処理ポリシーがないときは記録しない。ポーラーのハンドラーも同じ |
| 再送信 | 記録したジョブをそのまま再送信すると動く。実行してよいクラスにないものは拒む |
| デッドレターキュー | 再処理ポリシーからの件数と `maxReceiveCount`。LocalStack で `StartMessageMoveTask` による DLQ 再処理 (moto にはないので、そこでは SDK の応答のスタブで確認する) |
| 接続テストと画面 | `GetQueueAttributes`。「ジョブ」の画面の件数、失敗、再送信、削除、DLQ 再処理。管理者だけ |
| コードの読み込み | 新しいプロセスで確認する。`zeitwerk:check` が通る。boot のファイルを読み込んだ状態で、Redmine AWS とこのプラグインが起動する |

`bin/test` は、プラグインのテストのあと、ジョブのまわりの Redmine 本体のテスト (メール、プロジェクト、Webhook、管理) を動かします。`bin/test --redmine` は、プラグインをインストールした状態で Redmine 本体のすべてのテストを動かします。CI はこちらです。Serverless のイメージのテストも、SQS のイベントからジョブを動かします ([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#jobs-redmine_aws_sqs))。

CI は、静的チェックとテストを Ruby 3.2 と 4.0 で実行します。ローカルでは、`RUBY_IMAGE=ruby:3.2 bin/test` (または `bin/lint`) で Ruby 3.2 で実行します。

テストには Redmine AWS が要ります。このリポジトリの隣の [redmine_aws](https://github.com/redmine-kit/redmine_aws) のチェックアウト (`../redmine_aws`) か、`REDMINE_AWS_DIR` に指定したパスです。CI はチェックアウトします。

プラグインのテストは、プラグイン自身のファイルのカバレッジ (SimpleCov。Cobertura XML の `coverage/coverage.xml`) も書きます。CI は、それを [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_sqs) に送ります。

```sh
bin/test            # プラグインのテストと、ジョブのまわりの Redmine のテスト
bin/test --redmine  # Redmine のすべてのテストも
REDMINE_AWS_DIR=<ディレクトリ> bin/test  # redmine_aws を <ディレクトリ> から
bin/lint            # RuboCop
bin/services --down # PostgreSQL、moto、LocalStack を止める
```

<a id="to-verify"></a>

## 未確認の事項

- 実際のキューでの、失敗の記録と DLQ 再処理 (テストは LocalStack か moto を使う)
- gem のポーラーをプロセスとして動かしたときの、ポーラーのハンドラー (テストはハンドラーを呼ぶ)
