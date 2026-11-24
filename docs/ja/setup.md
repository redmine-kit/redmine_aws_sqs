# 導入

Redmine Kit AWS SQS を使う Redmine に要るもの (インストール、設定、前提とする AWS リソース、IAM 権限、ネットワーク) です。[Serverless](https://redmine-kit.github.io/serverless/ja/) は、これらをすべて CloudFormation で作ります。このページは、手で用意するときや、Serverless が作るものを確認するときのためのものです。

<a id="requirements"></a>

## 動作環境

- Redmine 7.0 以降。
- AWS の gem `aws-activejob-sqs` 1.2 以降 (gem の依存です。チェックアウトでは、プラグインの `Gemfile` が追加します)。
- ジョブを動かすもの。AWS Lambda では、SQS のイベントソースと、ハンドラー `Aws::ActiveJob::SQS::LambdaHandler.job_handler` を持つ関数。Lambda 以外では、gem のポーラー (`aws_active_job_sqs`)。

<a id="required-plugins"></a>

### 必須プラグイン

| プラグイン | 用途 |
| --- | --- |
| [Redmine Kit AWS](https://github.com/redmine-kit/redmine_aws) | 「AWS」の管理メニューと、AWS のプラグインが共有する設定 |

ないときは、Redmine が起動時に停止し、そのプラグインの名前を示します。gem としてインストールすると、このプラグインがそれもインストールします ([インストール](#installation))。

<a id="optional-plugins"></a>

### オプションのプラグイン

| プラグイン | 使える機能 |
| --- | --- |
| [Redmine Kit Help](https://github.com/redmine-kit/redmine_help) | ヘルプのパネルに表示するこのプラグインのヘルプ |
| [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) | 新しい UI の「ジョブ」タブの画面 ([admin.md](admin.md#in-the-new-ui)) |

<a id="installation"></a>

## インストール

1. プラグインを gem としてインストールするか ([gem](#gem))、プラグインと、これが必要とする [Redmine Kit AWS](https://redmine-kit.github.io/redmine_aws/ja/) のチェックアウトを Redmine の `plugins/` に置きます ([gem を使わないとき](#without-the-gem))。順序は問いません。`redmine_kit_aws` がないときは、Redmine が起動時に停止し、その名前を示します ([必須プラグイン](#required-plugins))。
2. Redmine のフォルダーで `bundle install` を実行します。
3. プラグインのマイグレーションを実行します。

   ```sh
   bin/rails redmine:plugins:migrate RAILS_ENV=production
   ```

   失敗の記録のテーブル (`aws_sqs_job_failures`) と、「ジョブ」のタブに表示するキューの件数のテーブル (`aws_sqs_snapshots`) を作ります。
4. ほかの場所で `aws-activejob-sqs` を設定していれば、外します。`config/additional_environment.rb` のキューアダプターと、`config/aws_active_job_sqs.yml` です。どちらもプラグインが設定します。
5. Redmine を再起動します。

<a id="gem"></a>

### gem

**gem として** (推奨): Redmine の `Gemfile.local` に、GitHub Packages にある Redmine Kit のレジストリ (`https://rubygems.pkg.github.com/redmine-kit`。`bin/release` が公開します: [リリース](#releasing)) のブロックで追加します。このプラグインが必要とするプラグイン ([必須プラグイン](#required-plugins)) も Bundler がそこから取得し、これらの gem を rubygems.org から取得することはありません。レジストリには、公開のパッケージでも `read:packages` を持つ GitHub のトークンが必要です。Bundler には環境変数 `BUNDLE_RUBYGEMS__PKG__GITHUB__COM` (`<user>:<token>`) で渡し、リポジトリのファイルには書きません。

```ruby
# Redmine の Gemfile.local
source 'https://rubygems.pkg.github.com/redmine-kit' do
  gem 'redmine_kit_aws_sqs'
end
```

**リポジトリから** (開発用): Bundler は gem を git から取得します。Bundler は gem が必要とするプラグインを git からは取得しないので、その行も追加します。

```ruby
# Redmine の Gemfile.local
gem 'redmine_kit_aws', git: 'https://github.com/redmine-kit/redmine_aws.git', branch: 'main'
gem 'redmine_kit_aws_sqs', git: 'https://github.com/redmine-kit/redmine_aws_sqs.git', branch: 'main'
```

Bundler が `boot/redmine_kit_aws_sqs.rb` を読み込み、gem のフォルダーと、依存する gem の Redmine Kit AWS のフォルダーを Redmine のプラグインローダーに渡します。Redmine は `plugins/` のプラグインと同じく、gem の `init.rb` を実行し、アセット、文字列、ビュー、マイグレーションを使い、`lib/` と `app/` を Rails のコードローダーに追加し、ルートを追加するので、`plugins/` へのリンクは不要です。`plugins/` に同じ id のフォルダーがあれば、そちらが優先されます。 このファイルは、Rails の初期化より前に必要なことも行います。キューアダプターはそのときまでに設定する必要があり、Redmine が `init.rb` を実行するのでは遅すぎるからです。 gem には実行に必要なファイルが入り、プラグインの `Gemfile` は入りません。

<a id="without-the-gem"></a>

### gem を使わないとき

リポジトリを Redmine の `plugins/` にクローンします。フォルダー名は、リポジトリ名ではなく、プラグインの ID にします。

```sh
git clone https://github.com/redmine-kit/redmine_aws.git plugins/redmine_kit_aws
git clone https://github.com/redmine-kit/redmine_aws_sqs.git plugins/redmine_kit_aws_sqs
```

Redmine の `Gemfile` が読み込むプラグインの `Gemfile` が、プラグインをパスで指定するので、gem と同じく Bundler が Rails の初期化より前に `boot/redmine_kit_aws_sqs.rb` を読み込みます。隣のチェックアウトの Redmine Kit AWS もパスで指定します (どちらも、`Gemfile.local` かほかのプラグインの `Gemfile` がすでに指定していなければ)。`Gemfile.local` に行を追加する必要はありません。

<a id="configuration"></a>

## 設定

| キー | 説明 | パラメーター |
| --- | --- | --- |
| `REDMINE_SQS_QUEUE_URL` | ジョブキューの URL。これでプラグインが有効になる。起動時に読む | 必須。すべてのプロセス (web、ジョブ、rake) に設定する |

| 項目 | 説明 | 変える場所 |
| --- | --- | --- |
| キュー | Redmine のキュー `default` と `mailers` を、どちらもジョブキューに向ける | 変えられない (プラグインが設定する) |
| 実行を許可するジョブクラス | 一覧にないクラスのメッセージは実行しない (gem の `job_class_allowlist`)。一覧は下記 | ほかのプラグインが `RedmineKit::Aws::Sqs::Boot.allow_job` で追加する |
| デッドレターキュー | プラグインは、デッドレターキューと `maxReceiveCount` を、ここから読む (`GetQueueAttributes`)。専用の設定はない | ジョブキューの再処理ポリシー |

<a id="allowed-job-classes"></a>

### 実行を許可するジョブクラス

キューが実行するのは、次のジョブクラスだけです。

- `Mailer::DeliveryJob` (すべてのメール)
- `DestroyProjectJob` と `DestroyProjectsJob`
- `WebhookJob`
- ほかの Redmine Kit AWS のプラグインのジョブ: `AwsS3ReconcileJob` と `AwsSesReimportMailJob`
- ほかのプラグインが `RedmineKit::Aws::Sqs::Boot.allow_job` で追加するクラス

<a id="message-deletion"></a>

### メッセージの削除

gem は、ジョブが成功したらメッセージを消します。Lambda では、イベントの ARN からキューの URL (`https://sqs.<region>.amazonaws.com/...`) を作ります。ジョブキューについては、プラグインがその代わりに `REDMINE_SQS_QUEUE_URL` を使います。そのため削除は、ジョブと同じエンドポイント (プライベート DNS のないインターフェイスエンドポイントや、テストでのエミュレーター) に届きます。ほかのキューは、ARN から作った URL のままです。

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

テストは `test/` にあり、Redmine 標準のしくみで、Redmine 7.0.3 と PostgreSQL 16 で、Apple container がインストールされて動いていれば Apple container で、そうでなければ Docker で動かします (`CONTAINER_CLI=container` または `docker` で選べます)。1 台のマシンで同時に実行する redmine-kit のリポジトリのテストは 2 つまでで (`TEST_SLOTS`)、空きを待ってから始まります。SQS は [AWS Emulator](https://docs.aws.amazon.com/ja_jp/emulator/latest/userguide/) です (`bin/aws_emulator`。Docker では `test/compose.yml`)。AWS のパッケージから、`test/aws-emulator/Dockerfile` で固定したバージョンをインストールし、テレメトリーはオフにします。ログにバージョンを出します。プラグインが呼ぶ SQS の操作はすべてあるので、結合テストはモックしません。単体テストと機能テストは、SDK の応答のスタブを使います。

実行は、終わったときに (テストの成功、失敗、中断のいずれでも)、自分が起動したサービスのコンテナを停止します (削除はしません)。実行の前から動いていたコンテナと、このリポジトリの別の実行がまだ使っているコンテナは、そのまま動かしておきます。`KEEP_SERVICES=1` を指定すると、実行の後も動かしたままにします。

プラグインのテストは内部ネットワークで動き、AWS には接続できません。接続できるときは、テストが失敗します。エミュレーターの証明書には `127.0.0.1` と `localhost` しか含まれないので、テストはそのアドレスでエミュレーターに接続します。Docker ではエミュレーターのネットワーク名前空間で動かします。Apple container は名前空間を共有できないので、`127.0.0.1:9297` をエミュレーターのコンテナに転送し (`bin/aws_emulator`、`test/aws_forward.rb`)、コンテナから取り出した証明書を信頼します。Redmine 本体のテストは、AWS の API を呼びませんが、インターネットの名前を解決する (Webhook) ので、別のネットワークで動かします。エミュレーターはキューの URL を SQS の公開のホスト (`https://sqs.<region>.amazonaws.com/...`) で返しますが、そのホストでは応答しません。そのため、テストはエミュレーターが返したキューの URL をエミュレーターのエンドポイントに置き換えます (`test/test_helper.rb`。[エミュレーターの issue](https://github.com/aws/aws-emulator/blob/7753983c6e495ec3612695b1336bf4936fc7b7fd/issues/things-that-do-not-work/20261109T191027Z-sqs-queue-url-addressing-diverges-from-aws-createqueue.md))。

| 対象 | 確認すること |
| --- | --- |
| SQS でのジョブ | メールのジョブが `aws-activejob-sqs` で SQS に入り、Lambda が呼ぶハンドラーで動き、メールが送られる。`REDMINE_SQS_QUEUE_URL` がなければ、Redmine は標準のとおりにジョブを動かす |
| 許可の一覧 | 実行してよいクラスにないメッセージは動かさず、記録して消す |
| 失敗の記録 | 最後の受信 (再処理ポリシーから) で記録し、その前と、再処理ポリシーがないときは記録しない。ポーラーのハンドラーも同じ。ジョブ自身が発生させた `JSON::ParserError` はジョブのエラーで、決して実行できないメッセージとはせず、再試行する |
| 再送信 | 記録したジョブをそのまま再送信すると動く。実行してよいクラスにないものは拒む |
| 件数の更新 | `redmine_kit:aws:sqs:refresh` が、キューの件数を保存する。`REDMINE_SQS_QUEUE_URL` がないときと SQS を読めないときは失敗し、画面のためにエラーのクラスを保存する |
| 記録の保持 | `redmine_kit:aws:sqs:prune` が、90 日、または `DAYS` の日数より古い記録を削除する。1 から 99999 までの整数ではない `DAYS` では、メッセージを表示してタスクを中止し、何も削除しない |
| デッドレターキュー | 再処理ポリシーからの件数と `maxReceiveCount`。`StartMessageMoveTask` による DLQ 再処理 |
| 接続テストと画面 | `GetQueueAttributes`。「ジョブ」の画面の保存した件数 (画面は AWS の API を呼ばず、「最新の情報に更新」が呼ぶ)、失敗、再送信、削除、DLQ 再処理。システム管理者だけ |
| ネットワーク | プラグインのテストから AWS の SQS と STS に接続できない |
| コードの読み込み | 新しいプロセスで確認する。`zeitwerk:check` が通る。boot のファイルを読み込んだ状態で、Redmine Kit AWS とこのプラグインが起動する |

`bin/test` は、プラグインのテストを [Redmine Kit UI](https://github.com/redmine-kit/redmine_kit_ui) をインストールした状態 (隣のチェックアウト `../redmine_kit_ui` の `HEAD`。`REDMINE_KIT_UI` と `REDMINE_KIT_UI_REF` で別のものを選べます) と、インストールしない状態で動かし、そのあと、ジョブのまわりの Redmine 本体のテスト (メール、プロジェクト、Webhook、管理) を動かします。`bin/test --redmine` は、プラグインをインストールした状態で Redmine 本体のすべてのテストを動かします。CI はこちらです。Serverless のイメージのテストも、SQS のイベントからジョブを動かします ([Serverless の testing.md](https://redmine-kit.github.io/serverless/ja/testing.html#jobs-redmine_kit_aws_sqs))。

CI は、静的チェックとテストを Ruby 3.2 と 4.0 で実行します。ローカルでは、`TEST_RUBY=3.2 bin/test` (または `bin/lint`) で Ruby 3.2 で実行します。

`bin/test-gem` は、組織のプラグインのテンプレートと同じく gem を確認します。チェックアウトからプラグインと Redmine Kit AWS の gem をビルドし、チェックアウトを `plugins/` から外して [gem](#gem) のとおりにインストールし、すべてのファイルを読み込んで Redmine を起動します (`zeitwerk:check` と、起動時にすべてを読み込む production 環境)。各プラグインが gem のフォルダーから、boot のファイル、コード、ルート、マイグレーション、アセットとともに読み込まれることを確認し、チェックアウトを `plugins/` に戻して、チェックアウトが優先されることも確認します。。`bin/release` もこれを実行するので、gem にないファイルがあれば、Serverless がインストールする前に失敗します。

テストには Redmine Kit AWS が要ります。このリポジトリの隣の [redmine_kit_aws](https://github.com/redmine-kit/redmine_aws) のチェックアウト (`../redmine_kit_aws`) か、`REDMINE_KIT_AWS_DIR` に指定したパスです。CI はチェックアウトします。

`COVERAGE=1` を付けると、プラグインのテストは、プラグイン自身のファイルのカバレッジ (SimpleCov。Cobertura の XML の `coverage/coverage.xml`) も出力し、1 プロセスで実行します。CI は Ruby 4.0 でこれを有効にし、レポートを `plugin` フラグで [Codecov](https://codecov.io/gh/redmine-kit/redmine_aws_sqs) に送信します。送信の認証は OIDC (`id-token: write`) なので、トークンをシークレットに保存しません。Codecov のステータスは参考情報で、コミットや Pull Request を失敗にしません (`codecov.yml`)。

```sh
bin/test            # プラグインのテストと、ジョブのまわりの Redmine のテスト
bin/test --redmine  # Redmine のすべてのテストも
COVERAGE=1 bin/test # カバレッジを coverage/coverage.xml に出力する
REDMINE_KIT_AWS_DIR=<ディレクトリ> bin/test  # redmine_kit_aws を <ディレクトリ> から
bin/test-gem        # gem をビルド・インストールし、gem から、次に plugins/ から起動する
bin/lint            # RuboCop
bin/services --down # PostgreSQL と AWS Emulator を止める
```

新しい UI のモジュールは、`frontend/` で Node.js (バージョンは `frontend/.nvmrc`) を使って確認します。`.npmrc` には `ignore-scripts=true` があり、`@redmine-kit/ui` と `@redmine-kit/plugin` は、隣にある ui リポジトリのチェックアウト (`../../ui/packages/…`) から取得します。

```sh
cd frontend
npm install
npm run check       # 型チェック、コンポーネントのテスト (vitest)、ビルド、kit-check-ui、Storybook のビルド
npm run storybook   # タブの状態の Storybook (ポート 6008)
```

<a id="releasing"></a>
## リリース

`bin/release` は、gemspec のバージョンの gem を GitHub Packages の Redmine Kit のレジストリに公開します。実行できるのは変更のない `main` からだけで、バージョンが最後のタグ `v<version>` より新しいこと、必須プラグインがレジストリから範囲どおりに解決できること (`config/dependencies.yml`)、`bin/lint`、`bin/test`、`bin/test-gem` が成功することが条件です。公開には `~/.gem/credentials` のキー `github` (`:github: Bearer <token>`。`write:packages` を持つトークン) を使い、レジストリの読み取りには `BUNDLE_RUBYGEMS__PKG__GITHUB__COM` を使います。トークンはリポジトリにも出力にも含めません。署名付きのタグ `v<version>` を作り、それをプッシュするコマンドを表示します。バージョンはセマンティックバージョニングに従います。このプラグインを使うプラグインが動かなくなる変更ではメジャーバージョン (1.0 より前はマイナーバージョン) を上げ、それを必要とするプラグインの範囲も変えます。

<a id="to-verify"></a>

## 未確認の事項

- 実際のキューでの、失敗の記録と DLQ 再処理 (テストは AWS Emulator を使う)
- gem のポーラーをプロセスとして動かしたときの、ポーラーのハンドラー (テストはハンドラーを呼ぶ)
