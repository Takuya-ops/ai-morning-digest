# build 6 実装記録

2026年10月4日。初版設計のF01〜F13を実装対象とし、追加指示によりXタブ・投稿案タブ・X認証・検索・直接投稿を削除した。現行ナビゲーションは「今日・ライブラリ・設定」。過去版の記述より本書を優先する。App Storeへの提出とは別の変更である。

## 機能と入口

| ID | 実装 | 入口・主なファイル |
|---|---|---|
| F01 | 配信音声の秒単位再開、15秒送り戻し、15/30分・記事末尾タイマー、聴了区間の記録、ロック画面のシーク | ミニプレイヤー左の波形 → 再生詳細。`BriefingPlayer.swift` |
| F02 | 今日の音声の一括保存・進捗・停止・再試行、Wi-Fi限定自動取得、250 MiB・自動取得7日、手動保存ピン、SHA256とサイズ検証、共有取得・最大2通信 | 今日/設定 → ダウンロード。`MicrosoftAudio.swift`, `ExperienceViews.swift` |
| F03 | 3/5/10分・全件、声と速度を反映、実測時間・日本語判定付きのみ時間指定に採用、未聴→興味→元順序 | 今日の時間選択。`BriefingPlan` |
| F04 | 端末内の記事検索、NFKC・小文字化・最大5語AND、日付/カテゴリ/保存/未読 | ライブラリ → 検索。`SearchIndex` |
| F05 | キーワード/カテゴリ/媒体の非表示。保存・検索・再生中キューには影響しない | 設定 → 非表示。`MuteRules` |
| F06 | 本文push→固定原稿の音声生成→検証→音声push、revisionとcontentRevision、声別状態、音声だけ再実行、通知からの当日取得確認 | `publication.js`, `publish-audio.js`, `daily.yml` |
| F07 | 本物のGemini日本語WAVをバンドルして別プレイヤーで試聴、Gemini共通既定 | 初回案内。`VoicePreview`, `VoicePreferences` |
| F08 | Anthropic未設定時はGeminiで日本語要約/スタイル/Q&A。失敗時は原文、AI生成フラグなし。方法・言語・原稿ハッシュを配信 | `summarize.js`, `enrich.js`, `publication.js` |
| F09 | 複数コレクションと最大10,000字メモ、記事版の保持、コレクション削除でもメモ保持 | 記事末尾/ライブラリ。`ExperienceStore` |
| F10 | 5用語の同梱辞書、関連用語と公式リンク・確認日 | 記事末尾/設定。`GlossaryView.swift` |
| F11 | 日本時間の月曜始まり、週移動、取得日数・未取得日・既読/聴了/保存・カテゴリ集計 | ライブラリ → 週次 |
| F12 | Web音声選択、native controlsによる再生/一時停止/シーク、速度、次の記事、失敗表示 | Webトップ/日付別ページ。`audio-player.js` |
| F13 | 標準SwiftUI/Dynamic Type、重要操作の読み上げラベル、44pt操作域、状態のテキスト表示 | 追加画面とプレイヤー |

## 採用した設計上の変更

- 新機能の永続化は既存SQLiteの全面移行を避け、`LibraryRepository` actorとatomic JSON `library-v1.json`を追加した。既存SQLiteは既読/保存/日次本文を継続する。検索は正規化済みインデックスを別Taskで構築・検索する。初版のSQLite新テーブル/SQLは今回採用しない。
- 再生チェックポイントはUserDefaultsの版付きJSON。キュー、記事番号、音声、秒数、聴取した秒を保存し、起動後は停止状態で復元する。アプリの強制終了直前の最大約1秒は戻る場合がある。端末標準音声は記事の先頭から再開する。
- 同じURLの記事も日付付きeditionIDで検索/メモ/コレクションを分離。既読/保存マークは従来どおりURL単位で共通とし、既存データを引き継ぐ。公開原稿を同日更新した場合、メモの版キーは変わらない。
- ダウンロードは端末の前景Taskで実行し、OSに中断されたら再試行する。アプリ終了後のバックグラウンド転送は保証しない。日付・音声・取得版ごとのパックと全体を削除でき、再生中の1件は保護する。パックは取得時点の本文と音声を保持し、別パックと共用する音声は残す。手動保存記事はライブラリ検索でも保持する。
- 自動取得は明示的な設定オン時と再生時の先読み。Wi-Fi・非従量・非省データを確認する。iOSのバックグラウンド更新時刻は制御しない。
- 音声停止タイマーは壁時計で判定する。記事末尾停止は次の記事へ位置を進めて停止する。自動再生開始を伴う復元はしない。
- 音声の言語は配信原稿の日本語文字の有無に基づく簡易判定であり、翻訳品質の保証ではない。時間選択には日本語と実測メタデータの両方が必要。
- 用語辞書はLLM/RAG/TTS/トークン/コンテキストの5項目。公式文書を確認して日本語で短く説明する。利用者のメモや本文を追加のAI呼び出しへ渡さない。
- 週次振り返りはローカル記事の集計であり、AI作文・未取得記事の推測を行わない。過去の週は残存記事だけが対象。
- 既存のXキーを専用service/account指定で削除し、旧X検索キャッシュ・検索設定・ミュート設定を消す。旧SQLiteに既にあるdraftsテーブルは触らず、読み書きコードを削除する。X上の過去の投稿は操作しない。
- 本文と音声の公開は別commit。GitHub Pagesの配信反映には遅延がある。音声失敗でも本文commitは残る。本文/Pages公開確認後、Geminiの日次利用枠に限定して警告付き成功とする。Summaryに音声未配信と生成済み件数を明示し、公開JSONの音声はfailedのまま。その他の設定・認証・通信・公開/音声検証エラーはActionsも失敗する。利用枠回復後に `retry_audio` で再開する。一時エラーは最大3回の再試行、日次枠は即時停止。

## データ契約

配信ルートの `publication` は `revision`, `contentRevision`, `textState`, `updatedAt`, `audioByVoice`。状態は `pending/ready/failed/unavailable`、件数は `expectedCount/generatedCount`。

トピックの `editorial` は `method/language/status`、`narration` は `language/scriptHash`、`audioMetadata[voice]` は `durationSeconds/byteLength/mimeType/assetSHA256/scriptHash`。時間はWAVのdataチャンク長/byteRateから算出する。途中成功時は全件のGemini URLを除き、完全な声セットだけを公開する。任意の外部URLは音声検証/HTMLプレイヤーへ渡さない。

## 検証と残る実機確認

Nodeテストは公開状態遷移・原稿版不変・WAV不正/部分失敗・Web埋め込みのエスケープ・要約API失敗時の原文保持を含む。iOSテストは旧データ保持・配信音声・時間計画・検索正規化/版分離・非表示・ノート保持・書込順序・再起動停止状態を含む。1万記事の検索本体に300ms上限を置いたテストを追加した。これは実機p95の性能保証ではない。

VoiceOver全操作、最大文字サイズ全画面、低容量端末、Bluetooth切断・長時間ロック画面再生、実際の移動中の回線切替、試聴品質の本人評価は実機受入項目として残る。自動テストの成功でこれらを確認済みとは扱わない。

### 2026-10-04の実行結果

- Node: 最終変更で23件成功（利用枠エラーの秘匿診断テストを含む）。最終23件はGitHub Actions [checks 37166405894](https://github.com/Takuya-ops/ai-morning-digest/actions/runs/37166405894)でも成功。
- iOS: iPhone 18 Pro / iOS 27 Simulatorで23件成功（日付別保存の版維持・削除時のメモ保持を含む）。iOS 26.5は最終テスト時に起動待ちとなったため、成功結果に含めない。1万件検索はインデックス構築を除く検索部分で300ms未満のassertionを通過。
- Web: 実ブラウザでRelease音声の読み込み、1.2倍速、次の記事、一時停止を確認。人間による音質評価とは区別する。
- iOS build 6: 署名付きarchive生成とcodesign検証に成功。App Store提出・実機へのインストールは本変更の完了条件には含めない。

日次Actionsは本文・音声のpush後に[PagesビルドAPI](https://docs.github.com/en/rest/pages/pages#request-a-github-pages-build)を明示的に呼び、最後に公開JSONの本文版・revision・声別状態を最大5分間確認する。pushだけで配信済みとは扱わない。

本番のGemini 3.8 Flash要約APIでHTTP 503を確認したため、要約には一時エラーの最大3回試行と `gemini-2.5-flash` への切替を追加した。音声は指定どおりGemini 3.8 Flash TTSのまま。401/403はモデルを変えて再試行しない。モデル名は実APIの一覧で確認した。

TTSの429エラーは、構造化されたquotaId/quotaMetricから日次・分単位・不明の3分類だけを記録する。プロバイダのエラー本文、プロジェクト識別子、キー、原稿はログに出さない。既にReleaseへ保存した同一原稿の音声は再試行で再生成しない。

### 本番配信の確認結果（10月4日10時 JST）

- 最新本文は日本語10/10件で公開。本文のcontentRevisionを維持した `retry_audio` で音声だけを再試行した。
- [Actions 37166434006](https://github.com/Takuya-ops/ai-morning-digest/actions/runs/37166434006)でGemini TTSのHTTP 429を**日次利用枠**と特定。新原稿に対応するRelease WAVは4/10件で、公開JSONは声の状態をfailed・公開件数0とする。旧原稿の音声で代用しない。
- Pagesの公開JSONが生成した本文版・revision・声別状態と一致することをActionsで確認。最後の「Verify audio availability」は意図どおり失敗した。アプリ実装・checks成功と、本番音声の未配信を区別する。
- 音声全件の配信には利用枠の回復または運営側の利用枠見直しが必要。回復後はActions → daily-digest → Run workflow → `retry_audio` を有効にして実行すれば、生成済み4件を再利用する。課金・利用枠の変更は実施していない。[Google公式の利用枠説明](https://ai.google.dev/gemini-api/docs/rate-limits)

### 失敗通知への対応（10月4日）

本人からのdaily-digest失敗通知に対応し、本文の配信成功と音声の日次利用枠を分けて判定するよう変更した。`publication-outcome.js` は固定原稿のcontentRevision/revisionと処理結果を照合し、日次枠以外のエラーを警告へ変換しない。`report-publication.js` がActions Summary・警告・終了コードを出力する。HTTP 429の日次枠を最初のレスポンスで確認した時点で短時間の再試行を止める。

ローカルNodeテスト26件成功（既知の日次枠、認証/設定等の失敗、古い原稿の結果、本文失敗、不正件数、全件成功、日次枠を1回で停止する検証を含む）。iOSコードの変更なし。音声の生成完了や利用枠回復を意味する変更ではない。
