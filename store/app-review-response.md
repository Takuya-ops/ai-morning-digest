# App Review Notes — Guideline 4.2.2 / 1.0 (7)

更新: 2026-10-04。**再提出用ドラフト。App Store Connectには未反映・未送信です。**
旧1.0 (2)の動画を新ビルドの証拠として使わないでください。実機確認と本番配信を終え、実際に使える機能だけを残して提出します。

## 英文ドラフト

Hello App Review Team,

This version of AI Morning Digest has been redesigned around an on-device reading experience, offline library, and native iOS controls. Please try:

1. Reading: Open Today (今日) to browse the daily topics. Open an article to read its summaries and sources. Audio generation, playback and downloads have been disabled.

2. Daily reminders: In Settings (設定), enable the reminder, select the time, and choose weekdays or every day. Tap “2分後にテスト通知” to schedule a notification two minutes from now, then leave the app to see it. The notification opens Today, without starting audio. Notifications are scheduled locally for the next 30 days and renewed when the app runs.

3. WidgetKit: Add “AIダイジェスト” from the Home Screen widget gallery. The small widget shows one headline, the medium widget shows three, and a rectangular Lock Screen widget is also included. Tap a headline to open its article. The main app shares its latest headlines through an App Group. iOS determines actual background refresh timing.

4. Offline library: Open Today online and allow the initial download to finish. Enable Airplane Mode and reopen the app. The stored digest is displayed immediately. Library (ライブラリ) contains saved articles and a date-based archive, including the recent seven days when available. Downloaded thumbnails remain available offline. Older digests are pruned after 30 days; explicitly saved articles remain saved.

5. Personalization: Select topics during onboarding or in Settings. Followed topics appear first. Open an article to mark it read; use its Save button or swipe its list row to save it. Read state, bookmarks, topics, and completed days persist on-device. Articles use native views, with a source link at the end opening SFSafariViewController.

6. Article tools: Newly generated enriched digests include three summary styles and pre-generated questions and answers. AI-generated text is labeled and attributed. Older RSS-only digests indicate when additional summaries are unavailable. Native sharing can export a summary card with its source URL.

7. Search and learning: Library includes local-only keyword/date/category/read/saved search, collections and private notes, and weekly statistics with missing days explicitly listed. Article pages include an offline glossary with official source links. Notes stay on-device and are never sent to an AI service. X integration and posting features have been removed; ordinary iOS sharing remains.


There is no app account, advertising, subscription, or in-app purchase. Reading, reminders, and saved articles require no API keys. The public-news pipeline runs daily outside the app. Per-user questions are not sent to an AI service.

Thank you for your consideration.

## 提出前の確認

- [ ] build 7の署名付きアーカイブ・テスト結果を実装記録で確認。
- [ ] build 7を実機に導入し、記事閲覧・通知タップ・検索・機内モードを確認。
- [ ] VoiceOverと最大文字サイズ、Widget各サイズ・共有・Siriを実機確認。
- [ ] 新UIの提出用スクリーンショットを作成。旧版の画像や動画を新ビルドの証拠に流用しない。
- [ ] 3スタイル/Q&Aの現在の提供状態を確認し、審査説明を調整。
- [ ] App Privacy・年齢区分・App Store Connectの説明欄を更新し、TestFlight転送と再提出を実施。

根拠: [Apple App Review Guidelines 4.2](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality)。機能追加によって承認が保証されるものではありません。
