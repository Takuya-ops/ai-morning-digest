# App Review Notes — Guideline 4.2.2 / 1.0 (6)

更新: 2026-10-04。**再提出用ドラフト。App Store Connectには未反映・未送信です。**
旧1.0 (2)の動画を新ビルドの証拠として使わないでください。実機確認と本番配信を終え、実際に使える機能だけを残して提出します。

## 英文ドラフト

Hello App Review Team,

This version of AI Morning Digest has been redesigned around an on-device morning briefing, offline library, and native iOS controls. Please try:

1. Audio briefing: Open Today (今日), choose the iPhone voice from the voice menu, and tap Play (再生). The app reads the daily topics in sequence using AVSpeechSynthesizer. The mini player offers pause, previous/next article, and 0.8x/1.0x/1.2x/1.5x speed. Audio uses the iOS playback audio session. Microsoft Nanami and Keita can also be selected when that day's pre-generated audio is available. Gemini 3.8 narration is the default pre-generated voice. Those files use AVAudioPlayer and are cached for offline playback. No microphone is used.

2. Daily reminders: In Settings (設定), enable the reminder, select the time, and choose weekdays or every day. Tap “2分後にテスト通知” to schedule a notification two minutes from now, then leave the app to see it. The notification opens Today, with optional playback on tap. Notifications are scheduled locally for the next 30 days and renewed when the app runs.

3. WidgetKit: Add “AIダイジェスト” from the Home Screen widget gallery. The small widget shows one headline, the medium widget shows three, and a rectangular Lock Screen widget is also included. Tap a headline to open its article. The main app shares its latest headlines through an App Group. iOS determines actual background refresh timing.

4. Offline library: Open Today online and allow the initial download to finish. Enable Airplane Mode and reopen the app. The stored digest is displayed immediately. Library (ライブラリ) contains saved articles and a date-based archive, including the recent seven days when available. Downloaded thumbnails remain available offline. Older digests are pruned after 30 days; explicitly saved articles remain saved.

5. Personalization: Select topics during onboarding or in Settings. Followed topics appear first. Open an article to mark it read; use its Save button or swipe its list row to save it. Read state, bookmarks, topics, and completed days persist on-device. Articles use native views, with a source link at the end opening SFSafariViewController.

6. Article tools: Newly generated enriched digests include three summary styles and pre-generated questions and answers. AI-generated text is labeled and attributed. Older RSS-only digests indicate when additional summaries are unavailable. Native sharing can export a summary card with its source URL.

7. Listening and library tools: Choose a 3/5/10-minute briefing on Today using verified Japanese audio durations. Open the mini-player waveform for a seek bar, 15-second skip, and sleep timer. Playback position persists, but reopening the app does not autoplay. Download audio from Today or Settings before going offline; the app shows progress and storage use.

8. Search and learning: Library includes local-only keyword/date/category/read/saved search, collections and private notes, and weekly statistics with missing days explicitly listed. Article pages include an offline glossary with official source links. Notes stay on-device and are never sent to an AI service. X integration and posting features have been removed; ordinary iOS sharing remains.


There is no app account, advertising, subscription, or in-app purchase. Reading, reminders, saved articles, and device speech require no API keys. The public-news pipeline runs daily outside the app. Per-user questions are not sent to an AI service.

Thank you for your consideration.

## 提出前の確認

- [x] build 6署名付きアーカイブを生成し、Node20件・iOS22件テスト成功。
- [ ] build 6を実機に導入し、ロック画面・割り込み・Bluetooth・通知タップ・機内モードを確認。
- [ ] VoiceOverと最大文字サイズ、Widget各サイズ・共有・Siriを実機確認。
- [ ] 新UIの提出用スクリーンショットを作成。旧版の画像や動画を新ビルドの証拠に流用しない。
- [ ] 配信音声と3スタイル/Q&Aの現在の提供状態を確認し、審査説明を調整。
- [ ] App Privacy・年齢区分・App Store Connectの説明欄を更新し、TestFlight転送と再提出を実施。

根拠: [Apple App Review Guidelines 4.2](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality)。機能追加によって承認が保証されるものではありません。
