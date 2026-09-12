# App Review Notes — Guideline 4.2.2 / 1.0 (3)

更新: 2026-09-12。**再提出用ドラフト。App Store Connectには未反映・未送信です。**
旧1.0 (2)の動画を新ビルドの証拠として使わないでください。実機確認と本番配信を終え、実際に使える機能だけを残して提出します。

## 英文ドラフト

Hello App Review Team,

This version of AI Morning Digest has been redesigned around an on-device morning briefing, offline library, and native iOS controls. Please try:

1. Audio briefing: Open Today (今日), choose the iPhone voice from the voice menu, and tap Play (再生). The app reads the daily topics in sequence using AVSpeechSynthesizer. The mini player offers pause, previous/next article, and 0.8x/1.0x/1.2x/1.5x speed. Audio uses the iOS playback audio session. Microsoft Nanami and Keita can also be selected when that day's pre-generated audio is available. Those files use AVAudioPlayer and are cached for offline playback. No microphone is used.

2. Daily reminders: In Settings (設定), enable the reminder, select the time, and choose weekdays or every day. Tap “2分後にテスト通知” to schedule a notification two minutes from now, then leave the app to see it. The notification opens Today, with optional playback on tap. Notifications are scheduled locally for the next 30 days and renewed when the app runs.

3. WidgetKit: Add “AIダイジェスト” from the Home Screen widget gallery. The small widget shows one headline, the medium widget shows three, and a rectangular Lock Screen widget is also included. Tap a headline to open its article. The main app shares its latest headlines through an App Group. iOS determines actual background refresh timing.

4. Offline library: Open Today online and allow the initial download to finish. Enable Airplane Mode and reopen the app. The stored digest is displayed immediately. Library (ライブラリ) contains saved articles and a date-based archive, including the recent seven days when available. Downloaded thumbnails remain available offline. Older digests are pruned after 30 days; explicitly saved articles remain saved.

5. Personalization: Select topics during onboarding or in Settings. Followed topics appear first. Open an article to mark it read; use its Save button or swipe its list row to save it. Read state, bookmarks, topics, and completed days persist on-device. Articles use native views, with a source link at the end opening SFSafariViewController.

6. Article tools: Newly generated enriched digests include three summary styles and pre-generated questions and answers. AI-generated text is labeled and attributed. Older RSS-only digests indicate when additional summaries are unavailable. Native sharing can export a summary card with its source URL.

7. Optional X tools: The X tab searches public X posts using the user's own X API credentials. Drafts (投稿案) prepares 10 editable news-post alternatives without credentials. Direct posting requires the user's own Read and write credentials, an account check, and a final send confirmation. Credentials are stored in the device Keychain and sent only to X. No posts are sent automatically. These optional functions are separate from the no-login news reader.

There is no app account, advertising, subscription, or in-app purchase. Reading, reminders, saved articles, and device speech require no API keys. The public-news pipeline runs daily outside the app. Per-user questions are not sent to an AI service. X usage is subject to the user's X developer account and applicable API charges.

Thank you for your consideration.

## 提出前の確認

- [x] 開発署名のRelease 1.0 (3)をiPhone 15 Proへインストールし、起動・稼働を確認（2026-09-12）。TestFlight転送と以下の実機操作検証は未実施。
- [ ] 本番バッチを更新し、3スタイル・Q&A・Nanami/Keitaの配信を確認。キー未設定の現状では該当説明を調整する。
- [ ] ロック・他アプリ・消音スイッチ・着信/割り込み後の音声再生を実機検証する。
- [ ] 通知受信だけでなく通知タップ→今日→再生を実機確認する。
- [ ] Widget各サイズ・タップ遷移、機内モード、共有、Siriを実機確認する。
- [ ] X連携を実際の権限で検証し、必要な審査アクセス方法を用意する。秘密キーを公開資料に記載しない。
- [ ] X表示の追加に合わせ、年齢区分・UGC関連回答・App Privacyを確認する。
- [ ] 新ビルドのスクリーンショット・必要なら実機動画を用意する。
- [ ] App Store Connectの欄で文字数を確認し、必要な手順に絞る。

根拠: [Apple App Review Guidelines 4.2](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality)。機能追加によって承認が保証されるものではありません。
