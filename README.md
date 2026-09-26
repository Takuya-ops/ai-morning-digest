# 🌅 生成AIモーニングダイジェスト

毎朝5:30(JST)に、国内外30以上のメディア・ベンダー公式ブログから**生成AI関連ニュースを抜け漏れなく収集**し、
**大きなトピック順のTOP10 + その他全記事**を1ページにまとめて自動公開するアプリです。

📖 **毎朝ここを見る** → https://takuya-ops.github.io/ai-morning-digest/

## 旧版のデモ動画（build 2）

改修前のiPhone画面で、ニュースTOP10、通知時刻の設定、過去の日付の閲覧、参照元の記事の確認を55秒で紹介しています。今回のbuild 4の画面とは異なります。

**[▶ デモ動画を確認したい方はこちら（AIナレーション付き）](https://takuya-ops.github.io/ai-morning-digest/demo/ai-digest-short-narrated.mp4)**

<a href="https://takuya-ops.github.io/ai-morning-digest/demo/ai-digest-short-narrated.mp4"><img src="docs/demo/thumbnail.jpg" alt="生成AIモーニングダイジェストのデモ動画を見る" width="240"></a>

- [AIナレーション付きで見る](https://takuya-ops.github.io/ai-morning-digest/demo/ai-digest-short-narrated.mp4)
- [ナレーションなしで見る](https://takuya-ops.github.io/ai-morning-digest/demo/ai-digest-short-no-narration.mp4)

どちらも字幕・赤枠・BGM・効果音付きです。動画内のニュースは収録時点の内容です。

## 特徴

- **抜け漏れ防止**: ITmedia AI+ / 日経クロステック / Publickey / GIGAZINE / OpenAI / Google / DeepMind / TechCrunch / The Verge / Hacker News など国内外32媒体のRSSを毎朝取得。TOP10に入らなかった記事も「その他」欄に全件掲載します。
- **大きなトピック順に表示**: 同じ話題を報じる記事を日英またいで自動でまとめ、「何媒体が報じたか×媒体の影響度」でスコアリングしてTOP10を表示します。
- **ニュースの内容まで分かる**: 各トピックに日本語の要約(2〜4文)と「なぜ重要か」を掲載。`ANTHROPIC_API_KEY` を設定するとClaude(claude-opus-5)が要約を生成し、未設定でも記事の説明文から要約を組み立てます。
- **見やすさ重視**: スマホ対応・ダークモード対応の1カラムレイアウト。ランキングバッジ、ソースチップ、折りたたみ式の関連記事一覧。

## 📱 iOSアプリ(ネイティブ)

[ios/](ios/) にSwiftUI製のネイティブiPhoneアプリ「AIダイジェスト」があります。

- **今日 / X / 投稿案 / ライブラリ / 設定**の5タブ。記事はアプリ内で読み、出典だけをアプリ内Safariで開きます。
- **音声ブリーフィング**: プルダウンでMicrosoft **Nanami / Keita**、iPhone標準音声を選択。Microsoft音声は日次バッチで事前生成するMP3をAVAudioPlayerで再生・保存し、標準音声はAVSpeechSynthesizerを使用。再生・一時停止・記事送り・4段階速度・ミニプレイヤー・バックグラウンド音声とロック画面操作の実装を含みます（実機での最終検証は未実施）。
- **通知**: 既定7:00、平日/毎日、タップで再生、2分後のテスト通知。30日先までローカル予約し、起動/バックグラウンド更新で延長。未来の日付に古い見出しを表示しません。
- **オフライン**: SQLiteに当日＋直近7日を取得、30日保持。旧キャッシュを移行し、保存記事は保持期限後も残します。バックグラウンド取得の実行時刻はiOSが決めます。
- **読む・振り返る**: 興味トピック、保存/既読、日付・カレンダーアーカイブ、要約3種・Q&A（新形式の配信分）、画像カード共有、読了記録、Siriショートカット。
- **WidgetKit**: Small / Medium / ロック画面。App Groupで最新の見出しを共有します。
- **Xの情報**: 自分のAPIキーを設定し、手動更新で最大10投稿を検索。原文・投稿者・出典を表示し、アカウントの非表示とXでの報告への導線を用意。
- **投稿案**: 取得記事から10案、端末内で編集・保存。キーなしでも共有シートが使えます。本人用の4つのキーとRead and write権限があれば、投稿先確認→内容確認→送信でXに直接投稿。タイムアウト時は再送せず結果確認が必要な状態にします。

実装範囲・検証結果・残る再提出手順は [store/implementation-status.md](store/implementation-status.md) を参照してください。App Storeの承認・再提出はまだ行っていません。

### 要約生成とXの設定

現在の配信先は既存の `data/latest.json` と `data/YYYY-MM-DD.json` を維持しています。v2は `summaryStyles`, `ttsText`, `topics`, `faq`, `aiGenerated`, `socialDrafts` と記事ごとの `audio` を追加し、旧アプリ用の `summary` 文字列を保持します。

1. 3スタイル・Q&Aを日次生成するには、リポジトリのActions Secretに `ANTHROPIC_API_KEY` を設定します。未設定時はRSSの説明文と端末内の投稿案構成で動作します。利用者ごとにLLMを呼びません。
2. Xは各利用者がアプリの「設定 → X連携」でキーを登録します。Read and writeを有効にした自分のX開発者アプリのAPI Key / API Key Secret / Access Token / Access Token Secretを使用します。検索のみならBearer Tokenも利用できます。
3. キーは端末専用Keychainに保存します。アプリに共通キーを埋め込んだり、GitHub Pagesに公開したりしません。Xには自身のAPI利用料金・制限が適用されます。

Xの実アカウントへの投稿テストは未実施です。[X APIの認証](https://docs.x.com/fundamentals/authentication/guides/v2-authentication-mapping)・[料金](https://docs.x.com/x-api/getting-started/pricing)を確認してください。

#### 「3行・詳細・やさしく」が切り替わらない場合

この3種類は運営側が事前生成する機能です。**アプリ利用者のAPIキー設定は不要**で、Xのキーとも別です。未配信の記事はRSSの説明文だけを表示します。build 4では、空欄・欠落・同じ内容のスタイルを切り替え候補に出さず、未配信の理由を表示します。

運営側で有効化する手順:

1. この変更を本番の `main` に反映する。
2. GitHubリポジトリの Settings → Secrets and variables → Actions に `ANTHROPIC_API_KEY` を設定する（キーをソースや公開JSONへ書かない）。
3. Actions → daily-digest → Run workflow を `main` に対して実行する。
4. Pagesへの配信後、`data/latest.json` の `topics[].summaryStyles.short/detail/simple` に異なる本文が入ったことを確認し、アプリの今日タブで更新する。過去の記事は自動では再生成しない。

2026-09-12の確認時点ではSecret一覧が空で、公開中の10トピックに3種類の要約はありませんでした。キーを設定しても、クレジット・モデル権限・通信等で生成に失敗する場合は説明文へ戻ります。成功したかは配信JSONまで確認してください。

#### アイコン

build 4で、濃紺を背景に朝日とニュースの行を組み合わせたマークへ更新しました。iOS・PWAの素材を統一しています。[調査した公式資料・デザイン方針・再出力方法](design/README.md)。

### Microsoft Nanami / Keita の音声配信

1. 運営側のAzure Speechリソースを用意します。日次の公開ニュース文だけをMicrosoftへ送り、利用者の閲覧履歴や入力は送信しません。
2. GitHub Actions Secret `AZURE_SPEECH_KEY` と、Actions Variable `AZURE_SPEECH_REGION`（例 `japaneast`、作成したリソースと同じリージョン）を設定します。Speechの料金プラン・上限は運営側で管理します。
3. `daily-digest` が要約後にNanamiとKeitaの2種類を生成します。1日最大10記事×2音声、同じ文章・音声は再実行時に再利用します。利用者ごとの音声生成費用は発生しませんが、運営側のAzure Speech利用料はプランと文字数に応じます。
4. MP3を `digest-audio-YYYY-MM-DD` のGitHub Release assetsに保存し、配信JSONの各トピックに `audio["ja-JP-NanamiNeural"]` / `audio["ja-JP-KeitaNeural"]` のHTTPS URLを載せます。MP3を日々gitにコミットしない設計です。GitHubの `GITHUB_TOKEN` はワークフローから自動提供し、`contents: write` を使います。
5. アプリの「今日 → 音声」または「設定 → 読み上げ音声」で選択します。取得済み音声は30日保持し、圏外でも再生可能です。初回取得は通信が必要です。未配信の過去記事や「その他の記事」は標準音声で再生してください。

Azureキーがないときは音声の生成をスキップします。UIは未配信であることを明示し、Nanamiを選んだのに別の声を流すことはありません。初期選択は端末音声ですが、未選択の利用者にNanamiが全記事分届いた時点でNanamiを既定にします。キーはiOSバイナリやJSONには含めません。

音声生成の疎通・音質確認はAzure設定後に必要です。[Microsoftの日本語音声一覧](https://learn.microsoft.com/ja-jp/azure/ai-services/speech-service/language-support?tabs=stt-tts)・[公式REST API](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)に基づきます。非公式のEdge TTSエンドポイントは利用しません。

### ビルドとテスト

```sh
npm ci
npm test
xcodebuild -project ios/AIDigest.xcodeproj -scheme AIDigest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Xcode 26.6で開発、最低iOS 16。外部iOSライブラリは不要です。実機・配布ビルドにはアプリ本体とウィジェット両方の署名、App Group `group.com.takuyaops.aidigest` が必要です。

**iPhone実機へのインストール**(Apple IDがあれば無料):

1. Macで `ios/AIDigest.xcodeproj` をXcodeで開く
2. プロジェクト設定 → Signing & Capabilities → Team に自分のApple IDを設定
3. iPhoneをUSB接続し、実機を選んで ▶ Run
4. 初回はiPhone側で 設定 → 一般 → VPNとデバイス管理 から開発者を信頼

> 無料のApple IDの場合、署名は7日で期限切れになるため週1回の再インストールが必要です(有料のDeveloper Programなら1年)。

## 📱 スマホ版(PWA)

このサイトはPWA対応です。ホーム画面に追加すると、専用アイコン付きの**アプリとして全画面で起動**し、オフラインでも直近に表示したダイジェストを開けます。

- **iPhone (Safari)**: サイトを開く → 共有ボタン → **「ホーム画面に追加」**
- **Android (Chrome)**: サイトを開く → メニュー(⋮) → **「ホーム画面に追加」(または「アプリをインストール」)**

## 毎朝の通知方法(いずれか)

1. **スマホアプリとして開く**: 上記の手順でホーム画面に追加(毎朝アイコンをタップするだけ)
2. **RSSで通知を受け取る**(おすすめ): RSSリーダー(Feedly、Reeder等)で `https://takuya-ops.github.io/ai-morning-digest/feed.xml` を購読すると、毎朝ダイジェスト1件が通知されます
3. **Slack通知**: リポジトリのSecretsに `SLACK_WEBHOOK_URL`(Incoming Webhook)を設定すると、毎朝TOP10がSlackに届きます

## 仕組み

```
GitHub Actions (毎日 20:30 UTC = 5:30 JST)
  └─ node src/index.js
       1. collect.js   … 32フィードを並列取得、過去26時間分にフィルタ、AI関連判定、重複除去
       2. cluster.js   … エンティティ(企業名・製品名)とタイトル類似度で同一トピックを日英またいで集約
       3. cluster.js   … ソース数×媒体ウェイトでトピックの「大きさ」をスコアリング → TOP10
       4. summarize.js … Claudeで日本語見出し・要約・「なぜ重要か」を生成(APIキーなしでもフォールバック動作)
       5. render.js    … docs/ にHTML・アーカイブ・JSON・RSSを出力
       6. notify.js    … (任意)Slack通知
  └─ docs/ をコミット → GitHub Pagesで公開
```

## セットアップ(フォークして使う場合)

1. このリポジトリをフォーク
2. Settings → Pages → Source を `main` ブランチの `/docs` に設定
3. (任意)Settings → Secrets and variables → Actions に以下を登録
   - `ANTHROPIC_API_KEY` … Claudeによる日本語要約を有効化
   - `SLACK_WEBHOOK_URL` … Slack通知を有効化
4. Actions タブから `daily-digest` を手動実行(workflow_dispatch)して初回生成

## ローカル実行

```bash
npm install
npm run digest          # docs/index.html が生成される
open docs/index.html
```

環境変数:

| 変数 | 既定値 | 説明 |
|---|---|---|
| `DIGEST_TOP_N` | `10` | 上位表示するトピック数 |
| `DIGEST_WINDOW_HOURS` | `26` | 収集対象の時間窓(時間) |
| `ANTHROPIC_API_KEY` | なし | 設定するとClaudeで要約生成 |
| `SUMMARY_MODEL` | `claude-opus-5` | 要約に使うClaudeモデル |
| `AZURE_SPEECH_KEY` | なし | 運営側のMicrosoft音声生成キー。未設定時は生成をスキップ |
| `AZURE_SPEECH_REGION` | なし | Speechリソースのリージョン（例 `japaneast`） |
| `GITHUB_TOKEN` / `GITHUB_REPOSITORY` | Actionsで自動提供 | 日次MP3をGitHub Release assetsに保存 |
| `SLACK_WEBHOOK_URL` | なし | Slack Incoming Webhook |
| `SITE_URL` / `REPO_URL` | 自動導出 | GitHub Actions上では `GITHUB_REPOSITORY` から自動導出(フォークしてもそのまま動作)。手動指定も可 |

## フィードの追加・削除

[src/feeds.js](src/feeds.js) の配列を編集してください。`weight`(1〜5)がトピックの大きさ算出に、
`aiOnly: false` のフィードには [src/keywords.js](src/keywords.js) のAI関連キーワードフィルタが適用されます。

> **メモ**: Anthropic公式・Meta AI・ledge.ai はRSSフィードを提供していないため直接収集していません(各社の発表はニュースメディア経由でカバーされます)。

## ライセンス

MIT
