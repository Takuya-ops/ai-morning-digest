# AIダイジェストのアイコン

2026-09-12、本人の依頼でiOS・PWA用を更新。

濃紺の背景、朝日を表す暖色の半円、ニュースの行を表す3本の太いバー。
文字を使わず、朝のニュースを読むアプリの意味を一つのマークにまとめました。
既存UIの暖色アクセントとの関係を保ち、小サイズでの輪郭と余白を優先しています。

## 調査した一次資料

- [Apple: Say hello to the new look of app icons, WWDC25](https://developer.apple.com/videos/play/wwdc2025/220/)
  - Messagesの背景と前景、Photosの重なり削減、Homeの装飾削減、Settingsの太い線を紹介。
  - この案には少ない要素、正面からの形、太い線、静的な立体効果の抑制を適用。
  - 本成果物はPNG。Icon Composerのレイヤー式Liquid Glassアイコンではありません。
- [Apple: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Google Play: Icon design specifications](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)
  - 正方形の全域を使い、外周の角丸と外側の影を素材に焼き込まない考え方を参照。
  - Androidアプリ自体は今回追加していません。

## 素材と再出力

`app-icon-source.png` はCodex内蔵画像生成で新規作成した不透明・正方形のマスター。
APIキーを使う画像生成CLIは使用していません。
`sh scripts/export-icons.sh` でiOS 1024、PWA 512/192、Apple Touch 180ピクセルへ出力。
マークはmaskableアイコンの中央安全領域にも収まる構成です。
過去のブログ・デモに埋め込まれた旧アイコンは歴史的な素材として保持。

### 生成プロンプト

Use case: logo-brand. Create one finished production iOS app icon artwork for a Japanese AI morning news digest app. 1024 by 1024 square image, full bleed opaque background, straight square corners (OS adds mask), no outer margins or device mockup. Sophisticated, beautifully composed bold minimalist editorial symbol: a radiant warm apricot/coral sunrise half-disc above two or three carefully spaced horizontal rounded ivory bars of decreasing width, together forming one cohesive abstract news/digest glyph. Background deep midnight ink navy with extremely subtle tonal variation. Sunrise has restrained warm gradient, rest of mark crisp simple and mainly flat frontal shapes. Central mark occupies roughly 60 percent width and 56 percent height, generous optical breathing room, centered as a whole, balanced geometry. Memorable mature premium mobile app identity, strong silhouette recognizable at 40 pixels. The semicircle and news bars must feel like an integrated unique emblem, not a generic weather icon. No letters, no AI text, no numbers, no words, no sparkle, no circuit, no robot, no brain, no decorative rays, no thin strokes, no glossy 3D bevel, no cast shadow, no border, no rounded-square container inside the canvas. Return only the single icon filling entire square.
