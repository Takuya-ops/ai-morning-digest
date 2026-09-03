# App Store 提出用メタデータ(下書き)

App Store Connectの各欄にそのまま貼り付けられる形で用意しています。

## 基本情報

| 項目 | 値 |
|---|---|
| アプリ名(30字以内) | 生成AIモーニングダイジェスト |
| サブタイトル(30字以内) | 毎朝のAIニュースを1分でキャッチアップ |
| バンドルID | com.takuyaops.aidigest |
| SKU | ai-morning-digest-ios |
| プライマリカテゴリ | ニュース |
| セカンダリカテゴリ | 仕事効率化 |
| 年齢制限 | 4+(制限対象コンテンツなし) |
| 価格 | 無料 |
| プライバシーポリシーURL | https://takuya-ops.github.io/ai-morning-digest/privacy.html |
| サポートURL | https://github.com/Takuya-ops/ai-morning-digest |

> アプリ名が既に取られている場合の代替案: 「AIモーニングダイジェスト」「生成AI朝刊ダイジェスト」

## 説明文

```
毎朝5:30、国内外32のメディア・AI企業公式ブログから生成AI関連ニュースを自動収集。
「どれだけ多くの媒体が報じたか」で今日の重要トピックTOP10をランキングし、
日本語の要約付きで届けるニュースダイジェストアプリです。

【特徴】
・大きなトピックから順に表示 — 同じ話題を報じる記事を日英またいで自動でまとめ、重要な順にTOP10を表示
・抜け漏れなし — TOP10に入らなかった記事もすべて「その他」欄に掲載
・毎朝の通知 — 好きな時刻(既定6:30)に通知が届き、起きたらすぐ今日のAIニュースを把握
・要約付き — 各トピックに日本語の要約。気になったら記事タップで元記事へ
・オフライン対応 — 圏外でも前回取得分を表示
・登録不要・完全無料・広告なし

【収集ソース(一部)】
ITmedia AI+ / 日経クロステック / Publickey / GIGAZINE / CNET Japan / ZDNET Japan /
OpenAI / Google / Google DeepMind / Microsoft / NVIDIA / Hugging Face /
TechCrunch / The Verge / MIT Technology Review / Ars Technica / Hacker News ほか

ChatGPT、Claude、Geminiなどの生成AIの動向を毎朝1分でキャッチアップしたい方に。
```

## キーワード(100字以内)

```
生成AI,AI,ニュース,ChatGPT,Claude,Gemini,LLM,人工知能,朝刊,ダイジェスト,テック,まとめ
```

## App Reviewメモ(審査担当者向け・英語)

```
This app is a news digest reader for generative-AI topics. It displays headlines,
short excerpts, and links from publicly available RSS feeds published by news outlets
and AI vendors, with full attribution and links to the original articles (similar to
an RSS reader). The digest data is aggregated once daily by an open-source pipeline
(https://github.com/Takuya-ops/ai-morning-digest) and served as static JSON on GitHub Pages.
The app collects no user data, requires no login, and uses only local notifications.
No demo account is needed.
```

## App privacy(プライバシー質問への回答)

- データ収集: **なし**(Data Not Collected)
- トラッキング: なし
- 第三者SDK: なし

## 輸出コンプライアンス

- `ITSAppUsesNonExemptEncryption = NO` をInfo.plistに設定済み(HTTPS標準通信のみ)→ 質問は自動スキップされます

## スクリーンショット

`store/screenshots/` に6.9インチ(1320×2868, iPhone 17 Pro Max)のスクリーンショットを用意済み。
App Store Connectの「6.9インチディスプレイ」欄にアップロードしてください(6.5インチ以下は自動流用されます)。

## 提出手順(Developer Program加入後)

1. Xcode → Settings → Accounts で加入済みApple IDにサインインしていることを確認
2. App Store Connect (https://appstoreconnect.apple.com) → マイApp →「+」→ 新規App
   - プラットフォーム: iOS / 名前・バンドルID・SKU: 上の表の通り
3. このリポジトリの `ios/` でアーカイブ&アップロード(Claudeに依頼すればコマンドで実行します):
   ```bash
   xcodebuild -project AIDigest.xcodeproj -scheme AIDigest -configuration Release \
     -destination 'generic/platform=iOS' -allowProvisioningUpdates archive \
     -archivePath build/AIDigest.xcarchive
   xcodebuild -exportArchive -archivePath build/AIDigest.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
   xcrun altool --upload-app -f build/export/AIDigest.ipa -t ios \
     --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>   # または Xcode Organizer から Distribute App
   ```
4. App Store Connectでビルドを選択 → メタデータ・スクリーンショットを貼り付け → 審査へ提出
