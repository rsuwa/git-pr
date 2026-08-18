# git-pr

[English](README.md) | 日本語

`git-pr` は、ターミナルから行う一般的な GitHub のプルリクエスト操作を
簡略化する、小さな Git サブコマンドです。

- 現在のブランチをプッシュする
- プルリクエストが存在しない場合は作成する
- 既存のプルリクエストがある場合は更新する
- 現在のプルリクエストのマージを要求するか、GitHub の自動マージを有効にする

インストール後は、次のように実行します。

```bash
git pr
```

## 依存関係のセットアップ

`git-pr` は `git` と GitHub CLI（`gh`）を外部コマンドとして実行します。
公式の手順に従って GitHub CLI をインストールし、認証してください。

```bash
gh auth login
gh auth status
```

GitHub Enterprise Server を使用する場合は、リポジトリの `origin` リモートで
使われているホストに対して認証します。

```bash
gh auth login --hostname ghe.example.com
gh auth status --hostname ghe.example.com
```

`git-pr` のインストール後、次のコマンドでローカル環境を確認します。

```bash
git pr doctor
```

`git pr doctor` は、使用するリポジトリ内で実行してください。Git リポジトリの
外部、または `origin` がないリポジトリで実行すると、`github.com` に対する
認証を確認します。

`git pr copilot` は任意の機能であり、単体で動作する GitHub Copilot CLI
（`copilot`）が `PATH` 上に必要です。`git-pr` は `copilot` を直接呼び出します。
代わりに旧 `github/gh-copilot` 拡張機能をインストールしないでください。
次のいずれかの公式な方法でインストールします。

```bash
# Cross-platform; requires Node.js 22 or later.
npm install -g @github/copilot

# macOS and Linux with Homebrew.
brew install --cask copilot-cli

# Windows with WinGet.
winget install GitHub.Copilot

# macOS and Linux official install script.
curl -fsSL https://gh.io/copilot-install | bash
```

環境で `curl | bash` が制限されている場合は、npm、Homebrew、または WinGet を
使用してください。

次に Copilot CLI を一度起動し、サインインして表示される案内に応答します。

```bash
copilot
git pr doctor --with-copilot
```

`git pr doctor --with-copilot` は、`copilot` 実行ファイルが `PATH` 上にあることを
確認します。Copilot アカウントへのアクセス権、組織のポリシー、サインイン状態は、
`git pr copilot` の実行時に Copilot CLI が確認します。

関連資料：

- GitHub CLI のインストール：<https://github.com/cli/cli#installation>
- GitHub CLI の認証：<https://cli.github.com/manual/gh_auth_login>
- GitHub Copilot CLI のインストール：
  <https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli>
- GitHub Copilot CLI の使い方：
  <https://docs.github.com/copilot/how-tos/copilot-cli/cli-getting-started>

## インストール

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/install.sh | bash
```

インストーラーは `git-pr` を `~/.local/bin` に配置します。このディレクトリが
`PATH` に含まれていることを確認してください。既定では、インストーラーは同じ
リリースから `SHA256SUMS` もダウンロードし、取得した `git-pr` を検証してから
インストールします。インストール後、`git pr doctor` を実行して GitHub CLI の
認証を確認してください。`latest` URL は、GitHub Release でその時点の最新として
指定されているリリースを参照します。再現可能なインストールにするには、
ダウンロードするインストーラーと本体の URL を両方とも固定します。

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/download/v0.3.7/install.sh |
  env \
    GIT_PR_INSTALL_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.7/git-pr" \
    GIT_PR_CHECKSUM_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.7/SHA256SUMS" \
    bash
```

`SHA256SUMS` をダウンロードせず、SHA256 を指定して取得するファイルを固定するには、
次のように実行します。

```bash
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/install.sh |
  env GIT_PR_INSTALL_SHA256="<expected-sha256>" bash
```

手動でインストールする場合：

```bash
set -e
mkdir -p ~/.local/bin
tmp_file=$(mktemp)
tmp_sums=$(mktemp)
cleanup() {
  rm -f "$tmp_file" "$tmp_sums"
}
trap cleanup EXIT
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/git-pr \
  -o "$tmp_file"
curl -fsSL https://github.com/rsuwa/git-pr/releases/latest/download/SHA256SUMS \
  -o "$tmp_sums"
expected=$(awk '$2 == "git-pr" { print $1 }' "$tmp_sums")
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp_file" | awk '{ print $1 }')
else
  actual=$(shasum -a 256 "$tmp_file" | awk '{ print $1 }')
fi
[ "$actual" = "$expected" ]
bash -n "$tmp_file"
chmod 755 "$tmp_file"
mv "$tmp_file" ~/.local/bin/git-pr
```

## 使い方

現在のブランチをプッシュし、そのブランチのプルリクエストを作成または更新します。

```bash
git pr
```

動作の概要：

| 状況 | 動作 |
| --- | --- |
| PR が存在しない | `git-pr` はベースブランチを解決して取得し、現在のブランチをプッシュしてから PR を作成します。 |
| PR が存在する | `git-pr` は現在のブランチをプッシュし、オプションで指定された項目だけを更新します。 |
| PR が存在し、タイトルや本文のオプションが指定されていない | 空でない本文は保持します。本文が空の場合は、コミットの内容から生成します。 |
| 既存の PR に `--no-edit` を指定 | タイトルと本文は編集しません。メタデータと、明示的に指定した `--base` による更新は行われることがあります。 |
| 既存の PR に `--fill`、`--fill-first`、または `--fill-verbose` を明示的に指定 | 既存の本文を、コミットから生成した内容で置き換えます。 |
| `git pr copilot --mode=update` | 既存の本文を保持し、生成した内容を `git-pr` が管理するマーカーブロック内に追加します。 |

プルリクエストを作成または更新し、自動マージを有効にします。

```bash
git pr -a --delete-branch
```

タイトルと本文を明示してプルリクエストを作成します。

```bash
git pr -t "Fix login redirect" -d "Updates the redirect target after login."
```

ファイルから本文を読み込みます。

```bash
git pr -t "Fix login redirect" -F /path/to/body.md
```

プルリクエストのテンプレートを使用します。

```bash
git pr --template .github/pull_request_template.md
```

新しいプルリクエストを作成するときにエディターを開きます。

```bash
git pr --editor
```

メタデータを追加します。

```bash
git pr --label bug,backend --reviewer alice,bob --assignee alice
```

Copilot CLI を使用し、差分からプルリクエストのタイトルと本文を生成します。

```bash
git pr copilot --mode=create
```

既存の内容を保持したまま、Copilot で既存のプルリクエストを更新します。

```bash
git pr copilot --mode=update
```

必要な依存関係と認証を確認します。

```bash
git pr doctor
git pr doctor --with-copilot
```

現在のブランチにある既存のプルリクエストで、自動マージを有効にします。

```bash
git pr auto-merge
```

現在のブランチにある既存のプルリクエストのマージを要求します。

```bash
git pr merge
```

自動マージを無効にします。

```bash
git pr auto-merge --disable-auto-merge
```

最新の GitHub Release から `git-pr` を更新します。

```bash
git pr update
```

既定では、`git pr update` は `git-pr` アセットをダウンロードし、リリースの
`SHA256SUMS` で検証します。シンボリックリンクとディレクトリは更新対象として
拒否し、チェックサムと Bash 構文の検証に成功した場合にのみ実行ファイルを
置き換えます。`latest` ではなく、固定したリリースから更新するには、
次のように実行します。

```bash
GIT_PR_UPDATE_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.7/git-pr" \
GIT_PR_UPDATE_CHECKSUM_URL="https://github.com/rsuwa/git-pr/releases/download/v0.3.7/SHA256SUMS" \
  git pr update
```

インストール済みのバージョンを表示します。

```bash
git pr --version
```

## リリースアセット

`install.sh` と `git pr update` が使用する各 GitHub Release では、次のアセットを
公開する必要があります。

- `git-pr`
- `install.sh`
- `SHA256SUMS`

`SHA256SUMS` はバイト単位で厳密に一致する必要があります。小文字の SHA-256
ダイジェストとファイル名の間に半角空白を2個置き、次の順序で、末尾が改行された
2行だけを含めます。

```text
<git-pr SHA-256>  git-pr
<install.sh SHA-256>  install.sh
```

`script/build-release-assets` を使用して、単体で動作する実行ファイルを
ステージングし、このファイルを生成します。ステージングディレクトリを作成または
変更する前に、ビルダーは `script/build-git-pr --check` を実行します。
正規のソースとコミット済みのルート実行ファイルに不整合があれば、処理を拒否します。
ステージングディレクトリには、リポジトリのルートや正規の `src/` ディレクトリ配下を
指定できません。リリースワークフローは、この3個のアセットだけを公開します。

リリースワークフローは、隔離されたステージングディレクトリでこれらのファイルを
ビルドし、アップロード前に、ルートファイルとの一致、チェックサム、Bash 構文、
バージョン、インストール処理、更新処理を検証します。リリースタグは `v` に
ステージングした `git-pr --version` の値を続けたものでなければならず、
アップロードの直前まで、`origin` 上でチェックアウトおよび検証したコミットを
指している必要があります。Linux と macOS の両方でタグとバージョンの一致を検証し、
Ubuntu の公開ジョブでは、両方のジョブが成功したあとにリモートタグの参照先も
検証します。

`src/*.bash` の各フラグメントが、開発用の正規ソースです。
`script/build-git-pr` の固定マニフェストは、フラグメントの厳密な集合と連結順序を
定義し、ルートの `git-pr` を決定論的に生成します。フラグメントの欠落、重複、
または一覧にないフラグメントがある場合は不整合として拒否します。ルートの
`git-pr` は、生成済みの単体リリース候補としてコミットおよびレビューし、
リポジトリ内のファイルに実行時依存してはなりません。CI とリリースのステージングは、
変更を加えない `./script/build-git-pr --check` を実行します。したがって、
検証したルートファイルのバイト列が、そのままリリースアセットとしてアップロード
されます。実行時に `source src/*.bash` で読み込むことは禁止されています。

リリースを使用する前に、次のコマンドで検証します。

```bash
gh release view v0.3.7 --json tagName,isDraft,isPrerelease,assets
curl -fsSL https://github.com/rsuwa/git-pr/releases/download/v0.3.7/SHA256SUMS
```

リリースを公開するときは、テストスイートの実行、チェックサムの生成、
ローカルのリリース形式によるインストールと更新のスモークテストを済ませてから、
アセットをアップロードします。

## リモートの扱い

`git-pr` は、`origin` という名前の Git リモートでのみ動作します。`origin` の存在を
確認し、既定のベースブランチを解決するときは GitHub リポジトリのデフォルト
ブランチを使用します。また、明示的な
`HEAD:refs/heads/<current-branch>` refspec を使い、現在のブランチだけを
プッシュします。既存の上流ブランチは `origin/<current-branch>` でなければ
なりません。ほかのリモートは選択できません。

既定のベースブランチは、次の順序で解決します。

1. 明示的に指定した `--base`
2. `branch.<name>.gh-merge-base`
3. GitHub リポジトリのデフォルトブランチ
4. ローカルの `origin/HEAD`

ローカルのコミット範囲または Copilot 用の差分を生成するとき、`git-pr` はまず
選択したベースを `origin` から取得します。既存の PR でメタデータだけを更新する
場合はローカルのベース ref がなくても動作します。ただし、既存の PR に対して
`--base` で変更先を明示した場合は、現在のブランチをプッシュする前に、その
ベースブランチを `origin` に対して確認します。

## オプション

| オプション | 説明 |
| --- | --- |
| `-b, --base <branch>` | ベースブランチ。既定では `branch.<name>.gh-merge-base`、リポジトリのデフォルトブランチ、ローカルの `origin/HEAD` の順に使用します。 |
| `-t, --title <title>` | プルリクエストのタイトル。 |
| `-d, --body <body>` | プルリクエストの本文。 |
| `-F, --body-file <path\|->` | プルリクエスト本文のファイル。`-` を指定すると、`gh` が標準入力から読み込みます。 |
| `-T, --template <path>` | `gh pr create` と Copilot の作成モードで使用する、プルリクエスト本文の初期テンプレート。新規作成時のみ。 |
| `-e, --editor` | プルリクエストの作成中にエディターを開きます。新規作成時のみ。 |
| `--label <label>` | ラベルを追加します。繰り返し指定と、カンマ区切りの値に対応します。 |
| `--reviewer <user>` | レビュー担当者を追加します。繰り返し指定と、カンマ区切りの値に対応します。 |
| `--assignee <user>` | 担当者を追加します。繰り返し指定と、カンマ区切りの値に対応します。 |
| `--fill`, `--fill-first`, `--fill-verbose` | プルリクエストの作成時に、GitHub CLI の自動入力機能を使用します。既存の PR では、本文をローカルでコミットから生成した内容に明示的に置き換えます。 |
| `--no-fill` | GitHub CLI に自動入力オプションを渡しません。新規作成時にタイトルまたは本文がない場合は、ローカルでコミットから生成します。既存の PR では、内容を明示しない限りタイトルも本文も更新しません。 |
| `--no-edit` | 既存のプルリクエストのタイトルと本文を更新しません。メタデータと、明示的に指定した `--base` による更新は行われることがあります。 |
| `-a, --enable-auto-merge` | プルリクエストの作成または更新後に、自動マージを有効にします。 |
| `-m, --merge-method <method>` | マージ方法：`merge`、`squash`、`rebase`。`--enable-auto-merge`、`git pr auto-merge`、または `git pr merge` が必要です。 |
| `--delete-branch` | マージ後にブランチを削除します。`--enable-auto-merge`、`git pr auto-merge`、または `git pr merge` が必要です。 |
| `--admin` | マージ要件を回避するため、`git-pr` のマージ操作では拒否します。意図的に要件を回避する場合は、`gh pr merge --admin` を直接使用してください。 |
| `--match-head-commit <sha>` | マージ時に、プルリクエストのヘッドコミットが指定した SHA と一致することを要求します。省略すると、`git-pr` はローカルの `HEAD` SHA を使用します。`--enable-auto-merge`、`git pr auto-merge`、または `git pr merge` が必要です。 |
| `--disable-auto-merge` | 現在の PR の自動マージを無効にします。`git pr auto-merge` でのみ指定できます。 |
| `--with-copilot` | `git pr doctor` で、任意機能の Copilot CLI 実行ファイルを必須として確認します。 |
| `--draft` | プルリクエストを下書きとして作成します。 |
| `-w, --web` | プルリクエストをブラウザーで開きます。 |
| `--version` | `git` や `gh` を要求せずに `git-pr <version>` を表示して終了します。 |

## Copilot

`git pr copilot` は任意の機能であり、単体で動作する GitHub Copilot CLI
（`copilot`）が必要です。`copilot` が見つからない場合、作成モードでは、
PR テンプレートが指定されていればそのテンプレートを使用し、指定されていなければ
GitHub CLI の自動入力機能を使用します。更新モードでは、既存の PR のタイトルと本文を
変更しません。

```bash
git pr copilot --mode=create --detail=verbose
```

Copilot のオプション：

| オプション | 説明 |
| --- | --- |
| `--mode <create\|update\|auto>` | `create` は新しい PR のタイトルと本文を生成します。`update` は既存の本文を保持し、生成した内容を管理対象のマーカーブロック内に追加します。`auto` は、プルリクエストの有無に応じて選択します。 |
| `--detail <normal\|verbose>` | 生成する本文の詳細度を指定します。 |
| `--language <en\|ja>` | 出力言語。既定では `GIT_PR_LANGUAGE`、`git-pr.language`、`en` の順に使用します。 |
| `--diff-exclude <path>` | Copilot に送信する差分からパスを除外します。繰り返し指定できます。 |

Copilot に関するプライバシー上の動作：

- 更新モードでは、PR 本文内で次のマーカーを使用します。
  `<!-- git-pr:copilot-update:start -->` と
  `<!-- git-pr:copilot-update:end -->`。ブロック外の手動で記述した内容は
  保持します。マーカーブロックが不正な場合、`git-pr` は PR を編集しません。
- 更新モードでは、生成内容の重複を避けられるように、現在の PR のタイトルと本文を
  Copilot に送信するプロンプトへ含めます。

- `git-pr` は、プロンプト、差分、タイトル、本文の一時ファイルをリポジトリ外の
  非公開一時ディレクトリに書き込み、プロセスの終了時に削除します。
- Copilot の実行または解析に失敗した場合、デバッグログは既定で
  `${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs` に保存されます。
  `GIT_PR_COPILOT_LOG` に空でない値を設定すると、生成に成功した場合もログを
  保持します。
- デバッグログは、既定ではプロンプト、差分、応答の内容を記録しません。
  デバッグのためにこれらの内容を意図的に保存する場合に限り、
  `GIT_PR_COPILOT_LOG_CONTENT=1` を設定してください。
- Copilot を実行する前に、一時ディレクトリを `chmod 700` で保護する必要があります。
  ログディレクトリを非公開にできない場合、デバッグログは保存しません。この
  プライバシー保護は、ファイルシステムが POSIX パーミッションを適用することを
  前提とします。

設定：

```bash
git config git-pr.language ja
git config --add git-pr.diffExclude generated
git config --add git-pr.diffExclude vendor
```

環境変数：

| 変数 | 説明 |
| --- | --- |
| `GIT_PR_INSTALL_URL` | `install.sh` が使用する URL を上書きします。 |
| `GIT_PR_CHECKSUM_URL` | `install.sh` が使用する `SHA256SUMS` の URL を上書きします。 |
| `GIT_PR_INSTALL_DIR` | `install.sh` が使用するインストール先ディレクトリを上書きします。 |
| `GIT_PR_INSTALL_SHA256` | `install.sh` がダウンロードするファイルに期待する SHA256。設定した場合、`SHA256SUMS` はダウンロードしません。 |
| `GIT_PR_LANGUAGE` | Copilot の既定の出力言語：`en` または `ja`。 |
| `GIT_PR_DIFF_EXCLUDES` | Copilot 用の差分から除外するパスをカンマ区切りで指定します。 |
| `GIT_PR_COPILOT_DIFF_MAX_BYTES` | Copilot に送信する差分の最大バイト数。既定値：`20000`。 |
| `GIT_PR_COPILOT_LOG_DIR` | Copilot のデバッグログを保存するディレクトリ。既定値：`${XDG_STATE_HOME:-$HOME/.local/state}/git-pr/copilot-logs`。`chmod 700` で保護できない場合、ログは保存しません。 |
| `GIT_PR_COPILOT_LOG` | 空でない値を設定すると、成功時にも Copilot のデバッグログを保持します。 |
| `GIT_PR_COPILOT_LOG_CONTENT` | 空でない値を設定すると、プロンプト、差分、応答の内容を Copilot のデバッグログに保存します。 |
| `GIT_PR_UPDATE_URL` | `git pr update` が使用する更新 URL を上書きします。 |
| `GIT_PR_UPDATE_CHECKSUM_URL` | `git pr update` が使用する `SHA256SUMS` の URL を上書きします。 |
| `GIT_PR_UPDATE_SHA256` | `git pr update` がダウンロードするファイルに期待する SHA256。設定した場合、`SHA256SUMS` はダウンロードしません。 |
| `GIT_PR_UPDATE_INSTALL_PATH` | `git pr update` が置き換える実行ファイルのパスを上書きします。 |

SHA256 の検証には、利用可能であれば `sha256sum` を使用し、なければ
`shasum -a 256` を使用します。`git pr update` はダウンロード前に、更新 URL、
チェックサムの取得元、インストール先を報告します。この状態メッセージでは、
URL のユーザー情報、クエリー文字列、フラグメントを伏せて表示します。

`git pr merge` は `--auto` を付けずに `gh pr merge` へ処理を委譲します。
これは、現在のプルリクエストで GitHub の Merge ボタンを押す操作に似ています。
リポジトリのルールとマージキューの状態によって、GitHub CLI はすぐにマージするか、
プルリクエストをマージキューへ追加します。`git pr auto-merge` は
`gh pr merge --auto` へ処理を委譲し、要件が満たされた時点で後からマージするよう
GitHub に要求します。

## 既存のプルリクエスト

現在のブランチに対するプルリクエストがすでに存在する場合、`git pr` はブランチを
プッシュし、オプションで指定されたメタデータを更新します。`--title` を指定しない
限り、タイトルは保持します。本文が空でない場合は、自動入力オプション、`--body`、
`--body-file`、または `git pr copilot --mode=update` を明示的に使用しない限り、
本文を保持します。既存の本文が空の場合、既定の `git pr` の動作ではコミットから
本文を生成します。

メタデータと明示的なベースブランチの更新を許可しつつ、タイトルと本文を編集しない
ようにするには、`--no-edit` を使用します。既存の PR に `--base` を指定した場合、
`git-pr` は現在のブランチをプッシュする前に、変更先のベースブランチが `origin` に
存在することを確認します。

## 開発

実行ファイルの実装を変更する場合は `src/` を編集し、コミット済みの単体実行
ファイルを再生成して確認します。

```bash
./script/build-git-pr
./script/build-git-pr --check
```

生成されたルートの `git-pr` を直接編集しないでください。ソースフラグメントと、
生成されたルートファイルの変更は一緒にコミットします。ビルダーはグロブ展開の順序
ではなく固定マニフェストを使用します。`--check` はファイルを変更せず、
マニフェスト、フラグメント、ルートファイルの不整合があれば失敗します。

検証スイートを実行します。

```bash
for script in git-pr install.sh script/build-git-pr script/build-release-assets \
  script/verify-release-assets script/verify-release-tag \
  test/test_helper.bash; do
  bash -n "$script"
done
for source in src/*.bash; do
  bash -n "$source"
done
./script/build-git-pr --check
shellcheck git-pr install.sh script/build-git-pr script/build-release-assets \
  script/verify-release-assets script/verify-release-tag \
  test/test_helper.bash test/*.bats
bats test
```

リリースワークフローで使用するファイルそのものをビルドし、検証します。

```bash
release_dir=$(mktemp -d)
./script/build-release-assets "$release_dir"
./script/verify-release-assets "$release_dir"
```

CI は Linux と macOS でこれらの検証を実行します。リリースの検証では、ローカルの
`file://` アセットと `SHA256SUMS` を使用し、リリース形式の `install.sh` と
`git pr update` の処理も実行します。

実際の Copilot CLI を使うスモークテストは任意で、既定ではスキップします。
このテストは Copilot に実際のリクエストを送信するため、アカウントのクォータと
時間を消費することがあります。実行するには `copilot` をインストールして認証し、
次のように設定します。

```bash
GIT_PR_RUN_REAL_COPILOT_SMOKE=1 npx -y bats test/real_copilot_smoke.bats
```

スモークテストは `timeout` を使用し、既定値は `30s` です。必要に応じて
`GIT_PR_REAL_COPILOT_SMOKE_TIMEOUT` で上書きします。

## ライセンス

MIT
