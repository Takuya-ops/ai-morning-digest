# App Review 返信文(Guideline 2.1 対応・Build 2 / 過去日付閲覧機能あり)

App Store Connect の **2か所**に貼り付けてください:
1. 対象アプリの審査メッセージ → 「App Reviewに返信」
2. 対象バージョン → 「App Review情報」→「メモ / Notes」

> 送信前の確認: 撮影時のiOSバージョンが下記(26.6.1)と一致しているか、iPhoneの「設定 → 一般 → 情報」で確認してください。動画は現ビルド(1.0 build 2)と同一コードで撮影されています。

---

## コピー用(英文・約3,100バイト)

```
Hello App Review Team,

Thank you for reviewing "生成AIモーニングダイジェスト". Below are our responses to Guideline 2.1.

1. Physical-device screen recording
Video (publicly accessible): https://takuya-ops.github.io/ai-morning-digest/app-review-demo-iphone15pro.mp4
Device: iPhone 15 Pro; iOS: 26.6.1; app version/build: 1.0 (2).
The recording begins with launching the app from the Home Screen and demonstrates the latest digest, browsing past-date digests via the calendar and previous/next controls, notification-time settings, related-article expansion, opening an original article, and the additional news list. This is the same build selected for the current App Store review.

2. Purpose and target audience
This is a native news reader that helps the general public - including developers, business users, and technology enthusiasts - stay current on generative AI. It saves time by grouping related coverage across outlets, ranking the day's top 10 topics, showing a short Japanese description for each, and listing all remaining articles so nothing is missed. Users can also browse digests from past dates and set an optional daily reminder.

3. Setup and access instructions
Internet access is required to download the daily digest and to open source websites. No account, login, reviewer API key, or sample files are required.
- Launch the app to see the latest digest (top 10 topics plus an additional-news list).
- Tap "related articles" to expand a topic, then tap an article to open its source website in the browser.
- Tap the calendar icon (top right) to pick a past date, or use the "previous day / next day / latest" controls under the date to move between days. Pull down to refresh.
- Tap the bell icon to enable a daily reminder and choose a time; allow notifications when prompted. Notifications are optional and not needed for reading.
There are no in-app accounts, in-app purchases, subscriptions, posting, comments, messaging, or uploads. The most recent latest digest is cached for offline reading.

4. External services and tools
Our aggregation runs server-side (outside the app): GitHub Actions runs a Node.js / rss-parser pipeline once daily, and GitHub Pages hosts the resulting static JSON, which the app fetches over HTTPS. The iOS app itself does not call any AI API. Daily reminders use Apple's on-device UserNotifications framework only; there is no remote push service, external authentication, or payment processor. Configured news sources include ITmedia AI+, ITmedia NEWS, Nikkei xTECH, Publickey, GIGAZINE, CNET Japan, ZDNET Japan, ASCII.jp, Impress Watch, INTERNET Watch, PC Watch, gihyo.jp, CodeZine, OpenAI, Google AI Blog, Google DeepMind, Microsoft Blog, NVIDIA Blog, Hugging Face, Mistral AI, Stability AI, AWS AI Blog, TechCrunch, The Verge, MIT Technology Review, Ars Technica, VentureBeat, The Decoder, Hacker News (via hnrss.org), Simon Willison, Zenn, and Qiita. An optional server-side summarization step (Anthropic Claude) and an optional Slack notification are disabled in production; the current production data uses the feeds' own descriptions.

5. Regional differences
There are no region-specific features or region-specific digest selection. The same data is served wherever the app is distributed. The interface is in Japanese; individual articles may be in Japanese or English. Digest dates and times are shown in JST, and reminders fire in the device's local time. The availability of linked external websites is outside our control.

6. Regulated services and third-party material
The app provides technology news only; it is not a regulated medical or financial service. It functions like an RSS reader: it displays third-party headlines and short descriptions taken from publicly published RSS/Atom feeds that the outlets provide for syndication, always with the source name shown and a link to the original article. Full article content is read on the source's own website; the app does not reproduce full articles and does not bypass any paywall or access restriction. Some sources (e.g., Zenn, Qiita, Hacker News) carry community-authored posts, which are likewise shown only as feed-provided headline/description with a link to the original. We respond promptly to any source's request to be removed from the app.

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
