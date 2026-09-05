# App Review 返信文(Guideline 2.1 対応・Build 2 / 過去日付閲覧機能あり)

App Store Connect の **2か所**に貼り付けてください:
1. 対象アプリの審査メッセージ → 「App Reviewに返信」
2. 対象バージョン → 「App Review情報」→「メモ / Notes」

> 送信前の確認: 撮影時のiOSバージョンが下記(26.6.1)と一致しているか、iPhoneの「設定 → 一般 → 情報」で確認してください。動画は現ビルド(1.0 build 2)と同一コードで撮影されています。

---

## コピー用(英文・約2,700文字 / 上限4,000字)

```
Hello App Review Team,

Thank you for reviewing "生成AIモーニングダイジェスト". Our responses to Guideline 2.1:

1. Screen recording (physical device)
Video: https://takuya-ops.github.io/ai-morning-digest/app-review-demo-iphone15pro.mp4
Device: iPhone 15 Pro; iOS 26.6.1; app 1.0 (2) - the build selected for this review.
It starts at app launch and shows the latest digest, browsing past-date digests via the calendar and previous/next controls, notification-time settings, expanding related articles, opening an original article, and the additional-news list.

2. Purpose and audience
A native news reader that helps the general public, developers, and business users stay current on generative AI. It groups related coverage, ranks the day's top 10 topics with short summaries, lists all remaining articles, offers past digests, and an optional daily reminder.

3. Setup and access
Internet is required to load the digest and open source sites. No account, login, API key, or sample files are needed. Launch for the latest digest; expand a topic and tap an article to open its source site; use the calendar or previous/next/latest controls for other dates; pull to refresh; tap the bell to set an optional daily reminder. There are no accounts, purchases, subscriptions, posting, comments, or uploads. The latest digest is cached for offline reading.

4. External services
Aggregation runs server-side (outside the app): a GitHub Actions pipeline collects public RSS/Atom feeds once daily, and GitHub Pages hosts the static JSON the app fetches over HTTPS. The app itself calls no AI API; reminders use Apple's on-device UserNotifications only - no remote push, external authentication, or payments. Sources are 30+ public feeds from news outlets and AI vendors (e.g., ITmedia, Nikkei xTECH, TechCrunch, The Verge, OpenAI, Google, NVIDIA); the full list is in our public repository: https://github.com/Takuya-ops/ai-morning-digest

5. Regional differences
None. The same data is served everywhere. The interface is Japanese; individual articles may be Japanese or English. Dates and times use JST; reminders fire in the device's local time.

6. Regulated services / third-party material
This is technology news, not a regulated medical or financial service. Like an RSS reader, it displays third-party headlines and short feed-provided descriptions, always with the source name and a link to the original article. Full articles are read on the source's own website; the app does not reproduce full articles or bypass any paywall. Community sources (e.g., Zenn, Qiita, Hacker News) are shown the same way. We remove any source promptly on request.

Thank you for your consideration.
```

---

## 日本語訳(社内確認用・提出不要)

1. **実機録画**: 動画URL・端末(iPhone 15 Pro)・iOS(26.6.1)・ビルド(1.0 build 2)を明記。起動→最新→過去日付(カレンダー/前日・翌日)→通知設定→関連記事→元記事→その他ニュースの流れ。審査対象と同一ビルド。
2. **目的・対象**: 生成AI動向を追う一般〜開発者向けニュースリーダー。関連記事の集約・TOP10・要約・抜け漏れ防止・過去日付・毎日のリマインダー。
3. **利用手順**: ログイン/APIキー/サンプル不要。最新表示、関連記事展開→元記事、カレンダー/前日翌日で過去日付、引っ張って更新、ベルで通知設定。アプリ内課金・投稿・アカウントなし。
4. **外部サービス**: 収集は端末外(GitHub Actions + rss-parser、GitHub Pagesが静的JSONを配信)。アプリはAIAPIを呼ばない。通知は端末内のUserNotificationsのみ。要約(Claude)とSlackは本番で無効。ソース一覧を列挙。
5. **地域差**: なし。全地域同一データ。UIは日本語、記事は日英。日時はJST、通知は端末ローカル時刻。
6. **規制・第三者コンテンツ**: 医療/金融の規制サービスではない。RSSリーダーと同様、各社が配信用に公開しているRSS/Atomの見出し+短い説明を出典名・元記事リンク付きで表示。全文は元サイトで閲覧、ペイウォール回避なし。Zenn/Qiita/HN等のコミュニティ投稿も同様。削除要請には速やかに対応。

---

## 送信前に最終確認する箇所

| 箇所 | 確認内容 |
|---|---|
| iOSバージョン | 「設定 → 一般 → 情報」で 26.6.1 か確認(違えば英文の iOS 行を修正) |
| 審査対象ビルド | 「配信 → iOSアプリ 1.0 → ビルド」で **1.0 (2)** が選択されていること(Build 1 から差し替え) |
| 動画URL | 上記URLがブラウザで再生できること(公開確認済み) |
