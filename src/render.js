import fs from 'node:fs';
import path from 'node:path';

// GitHub Actions上では GITHUB_REPOSITORY (owner/repo) からURLを自動導出する(フォークしてもそのまま動く)
const ghRepo = process.env.GITHUB_REPOSITORY;
const [ghOwner, ghName] = ghRepo ? ghRepo.split('/') : [];
const SITE_URL =
  process.env.SITE_URL ||
  (ghRepo ? `https://${ghOwner.toLowerCase()}.github.io/${ghName}` : 'https://takuya-ops.github.io/ai-morning-digest');
const REPO_URL =
  process.env.REPO_URL ||
  (ghRepo ? `https://github.com/${ghRepo}` : 'https://github.com/Takuya-ops/ai-morning-digest');

export function escapeHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const escapeXml = escapeHtml;

const jstDate = new Intl.DateTimeFormat('ja-JP', {
  timeZone: 'Asia/Tokyo', year: 'numeric', month: 'long', day: 'numeric', weekday: 'short',
});
const jstShort = new Intl.DateTimeFormat('ja-JP', {
  timeZone: 'Asia/Tokyo', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit',
});
const jstYmd = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Tokyo', dateStyle: 'short' });

export const toJstYmd = (d) => jstYmd.format(new Date(d));
const fmtDate = (d) => jstDate.format(new Date(d));
const fmtShort = (d) => jstShort.format(new Date(d));

const CSS = `
:root {
  --bg: #f6f5f1; --card: #ffffff; --text: #1f2328; --muted: #656d76; --line: #e4e2dc;
  --accent: #b4552d; --accent-soft: #fdf0e9; --chip: #f0eee8; --chip-text: #454c54;
  --gold: #c99700; --silver: #8a939e; --bronze: #a9714b; --link: #0a63b6;
  --rank-text: #ffffff;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #15171a; --card: #1e2126; --text: #e8eaed; --muted: #9aa3ad; --line: #33383f;
    --accent: #e58a5e; --accent-soft: #35271f; --chip: #2a2e34; --chip-text: #c4cad1;
    --gold: #e0b53f; --silver: #a8b2bd; --bronze: #c98f68; --link: #6cb2f0;
    --rank-text: #15171a;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--text);
  font-family: -apple-system, BlinkMacSystemFont, "Hiragino Kaku Gothic ProN", "Hiragino Sans",
    "Noto Sans JP", Meiryo, sans-serif;
  line-height: 1.75; font-size: 16px;
  -webkit-text-size-adjust: 100%;
}
a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
.wrap { max-width: 780px; margin: 0 auto; padding: 24px 16px 64px; }
header.site { margin-bottom: 8px; }
.site h1 { font-size: 1.5rem; margin: 0 0 4px; letter-spacing: 0.01em; }
.site .date { font-size: 1.05rem; font-weight: 600; color: var(--accent); }
.site .meta { color: var(--muted); font-size: 0.82rem; margin-top: 6px; }
.statbar { display: flex; flex-wrap: wrap; gap: 8px; margin: 14px 0 4px; }
.statbar span {
  background: var(--chip); color: var(--chip-text); border-radius: 999px;
  padding: 3px 12px; font-size: 0.78rem;
}
nav.links { margin: 10px 0 8px; font-size: 0.82rem; color: var(--muted); }
nav.links a { margin-right: 14px; }
nav.daynav { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 26px; }
nav.daynav a, nav.daynav .cur {
  background: var(--chip); color: var(--chip-text); border-radius: 999px;
  padding: 5px 14px; font-size: 0.82rem;
}
nav.daynav a:hover { text-decoration: none; opacity: 0.75; }
nav.daynav .cur { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
ul.arch { list-style: none; margin: 0; padding: 0; }
ul.arch li { margin-bottom: 14px; }
ul.arch .archdate { font-weight: 700; font-size: 1.0rem; }
ul.arch .archheads { margin: 6px 0 0; padding-left: 0; color: var(--muted); font-size: 0.86rem;
  list-style: none; }
ul.arch .archheads li { padding: 2px 0; border: none; margin: 0; }
h2.section {
  font-size: 1.05rem; margin: 40px 0 14px; padding-left: 10px;
  border-left: 4px solid var(--accent);
}
.topic {
  background: var(--card); border: 1px solid var(--line); border-radius: 14px;
  padding: 18px 20px 14px; margin-bottom: 16px;
}
.topic .head { display: flex; gap: 14px; align-items: flex-start; }
.rank {
  flex: 0 0 auto; width: 2.1rem; height: 2.1rem; border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  font-weight: 700; font-size: 1.05rem; background: var(--chip); color: var(--chip-text);
}
.rank.r1 { background: var(--gold); color: var(--rank-text); }
.rank.r2 { background: var(--silver); color: var(--rank-text); }
.rank.r3 { background: var(--bronze); color: var(--rank-text); }
.topic h3 { margin: 0; font-size: 1.08rem; line-height: 1.55; }
.topic h3 a { color: var(--text); }
.topic .summary { margin: 10px 0 0; font-size: 0.94rem; }
.topic .why {
  margin: 10px 0 0; font-size: 0.88rem; background: var(--accent-soft);
  border-radius: 8px; padding: 7px 12px;
}
.topic .sources { margin-top: 12px; display: flex; flex-wrap: wrap; gap: 8px; }
.srcchip {
  background: var(--chip); color: var(--chip-text); border-radius: 999px;
  font-size: 0.75rem; white-space: nowrap;
}
/* タップ領域はリンク側に持たせる(スマホでの押しやすさのため) */
.srcchip a { color: inherit; display: inline-block; padding: 5px 12px; }
.srcchip.more { padding: 5px 12px; }
.topic details { margin-top: 8px; }
.topic summary.toggle {
  cursor: pointer; color: var(--muted); font-size: 0.8rem; user-select: none;
  padding: 9px 0; /* タップ領域を確保 */
}
.articles { list-style: none; margin: 8px 0 4px; padding: 0; }
.articles li { padding: 5px 0; border-top: 1px dashed var(--line); font-size: 0.86rem; }
.articles .src { color: var(--muted); font-size: 0.78rem; margin-right: 8px; }
.articles time { color: var(--muted); font-size: 0.75rem; margin-left: 8px; white-space: nowrap; }
ul.others { list-style: none; margin: 0; padding: 0; }
ul.others li {
  padding: 9px 2px; border-bottom: 1px solid var(--line); font-size: 0.9rem; line-height: 1.6;
}
ul.others .src { color: var(--muted); font-size: 0.78rem; margin-right: 8px; }
ul.others time { color: var(--muted); font-size: 0.75rem; margin-left: 8px; white-space: nowrap; }
.errors { color: var(--muted); font-size: 0.78rem; margin-top: 26px; }
footer.site {
  margin-top: 48px; padding-top: 18px; border-top: 1px solid var(--line);
  color: var(--muted); font-size: 0.8rem;
}
.empty { color: var(--muted); background: var(--card); border: 1px dashed var(--line);
  border-radius: 12px; padding: 24px; text-align: center; }
/* 長い英語タイトルやURLが画面からはみ出さないようにする */
.topic h3, .articles li, ul.others li, .summary { overflow-wrap: anywhere; }
@media (max-width: 480px) {
  body { font-size: 15px; }
  .wrap { padding: 16px 12px 48px; }
  .site h1 { font-size: 1.28rem; }
  .site .date { font-size: 0.98rem; }
  .topic { padding: 14px 14px 12px; border-radius: 12px; }
  .topic .head { gap: 10px; }
  .topic h3 { font-size: 1.02rem; }
  .rank { width: 1.9rem; height: 1.9rem; font-size: 0.95rem; border-radius: 8px; }
  h2.section { margin-top: 32px; }
  nav.links a { margin-right: 10px; }
}
`;

function articleLi(a) {
  return `<li><span class="src">${escapeHtml(a.feedName)}</span><a href="${escapeHtml(a.link)}" target="_blank" rel="noopener">${escapeHtml(a.title)}</a><time>${fmtShort(a.date)}</time></li>`;
}

function topicCard(t) {
  const rankClass = t.rank <= 3 ? ` r${t.rank}` : '';
  const rep = t.articles[0];
  const chips = t.articles
    .slice(0, 8)
    .map((a) => `<span class="srcchip"><a href="${escapeHtml(a.link)}" target="_blank" rel="noopener" title="${escapeHtml(a.title)}">${escapeHtml(a.feedName)}</a></span>`)
    .join('');
  const extra = t.articles.length > 8 ? `<span class="srcchip more">+${t.articles.length - 8}</span>` : '';
  const why = t.whyItMatters
    ? `<p class="why">💡 ${escapeHtml(t.whyItMatters)}</p>` : '';
  const details = t.articles.length > 1
    ? `<details><summary class="toggle">関連記事 ${t.articles.length}件をすべて見る</summary><ul class="articles">${t.articles.map(articleLi).join('')}</ul></details>`
    : '';
  return `
<article class="topic">
  <div class="head">
    <div class="rank${rankClass}">${t.rank}</div>
    <h3><a href="${escapeHtml(rep.link)}" target="_blank" rel="noopener">${escapeHtml(t.headline)}</a></h3>
  </div>
  <p class="summary">${escapeHtml(t.summary)}</p>
  ${why}
  <div class="sources">${chips}${extra}</div>
  ${details}
</article>`;
}

const fmtNavDate = (ymd) => {
  const [, m, d] = ymd.split('-');
  return `${Number(m)}/${Number(d)}`;
};

export function renderPage(data, { isArchive = false, prevDate = null, nextDate = null } = {}) {
  const topics = data.topics.map(topicCard).join('\n');
  const others = data.others.length
    ? `<ul class="others">${data.others.map(articleLi).join('')}</ul>`
    : '<p class="empty">その他の記事はありません</p>';
  const errNote = data.stats.feedErrors.length
    ? `<p class="errors">⚠️ 取得できなかったソース: ${data.stats.feedErrors.map((e) => escapeHtml(e.feedName)).join('、')}</p>`
    : '';
  const topicsHtml = data.topics.length
    ? topics
    : '<p class="empty">対象期間内に生成AI関連のトピックが見つかりませんでした</p>';
  const prefix = isArchive ? '../' : '';
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>生成AIモーニングダイジェスト ${escapeHtml(data.date)}</title>
<meta name="description" content="毎朝届く生成AI関連ニュースのまとめ(${escapeHtml(data.date)})">
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#f6f5f1">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#15171a">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="AIダイジェスト">
<link rel="manifest" href="${prefix}manifest.webmanifest">
<link rel="icon" type="image/png" href="${prefix}icons/icon-192.png">
<link rel="apple-touch-icon" href="${prefix}icons/apple-touch-icon.png">
<link rel="alternate" type="application/rss+xml" title="生成AIモーニングダイジェスト" href="${prefix}feed.xml">
<style>${CSS}</style>
</head>
<body>
<div class="wrap">
<header class="site">
  <h1>🌅 生成AIモーニングダイジェスト</h1>
  <div class="date">${fmtDate(data.generatedAt)}</div>
  <div class="statbar">
    <span>📰 記事 ${data.stats.articleCount}件</span>
    <span>🗞️ ソース ${data.stats.feedCount}媒体</span>
    <span>🧵 トピック ${data.stats.topicCount}件</span>
    <span>⏰ ${fmtShort(data.since)} 〜 ${fmtShort(data.generatedAt)} (JST)</span>
  </div>
  <nav class="links">
    <a href="${prefix}feed.xml">📡 RSSで購読(朝の通知に)</a>
    <a href="${REPO_URL}" target="_blank" rel="noopener">GitHub</a>
  </nav>
  <nav class="daynav">
    ${prevDate ? `<a href="${prefix}archive/${prevDate}.html">← 前日 (${fmtNavDate(prevDate)})</a>` : ''}
    <span class="cur">${fmtNavDate(data.date)}</span>
    ${nextDate ? `<a href="${prefix}archive/${nextDate}.html">翌日 (${fmtNavDate(nextDate)}) →</a>` : ''}
    <a href="${prefix}archive/index.html">📚 日付一覧</a>
    ${isArchive ? `<a href="../index.html">⏩ 最新へ</a>` : ''}
  </nav>
</header>

<h2 class="section">今日の重要トピック TOP${data.topics.length || 10}</h2>
${topicsHtml}

<h2 class="section">その他の生成AIニュース(${data.others.length}件)— 抜け漏れ防止</h2>
${others}
${errNote}

<footer class="site">
  毎朝5:30(JST)に自動生成 / 生成時刻: ${fmtShort(data.generatedAt)} JST<br>
  ソース: 国内外${data.stats.feedCount}媒体のRSSを収集し、複数媒体が報じたトピックほど上位に表示しています。<br>
  <a href="${REPO_URL}" target="_blank" rel="noopener">ai-morning-digest</a> / <a href="${prefix}privacy.html">プライバシーポリシー</a><br>
  📱 スマホは「ホーム画面に追加」でアプリとして使えます
</footer>
</div>
<script>
if ('serviceWorker' in navigator) navigator.serviceWorker.register('${prefix}sw.js').catch(() => {});
</script>
</body>
</html>`;
}

function renderFeedXml(days) {
  const items = days
    .map((d) => {
      const top = d.topics.slice(0, 10);
      const desc = top.length
        ? `<ol>${top.map((t) => `<li>${escapeXml(t.headline)}</li>`).join('')}</ol>`
        : '本日のトピックはありません';
      const title = top.length
        ? `【生成AIダイジェスト ${d.date}】${top[0].headline} ほか${Math.max(top.length - 1, 0)}件`
        : `【生成AIダイジェスト ${d.date}】`;
      return `  <item>
    <title>${escapeXml(title)}</title>
    <link>${SITE_URL}/archive/${d.date}.html</link>
    <guid isPermaLink="true">${SITE_URL}/archive/${d.date}.html</guid>
    <pubDate>${new Date(d.generatedAt).toUTCString()}</pubDate>
    <description>${escapeXml(desc)}</description>
  </item>`;
    })
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>生成AIモーニングダイジェスト</title>
  <link>${SITE_URL}/</link>
  <description>毎朝5:30(JST)に届く、生成AI関連ニュースのまとめ</description>
  <language>ja</language>
${items}
</channel>
</rss>
`;
}

function renderArchiveIndex(entries) {
  const lis = entries
    .map(({ date, headlines }) => {
      const heads = headlines.length
        ? `<ul class="archheads">${headlines.map((h) => `<li>・${escapeHtml(h)}</li>`).join('')}</ul>`
        : '';
      return `<li class="topic" style="padding:14px 20px">
  <a class="archdate" href="${date}.html">📅 ${escapeHtml(fmtDate(`${date}T12:00:00+09:00`))}</a>
  ${heads}
</li>`;
    })
    .join('\n');
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>アーカイブ | 生成AIモーニングダイジェスト</title>
<meta name="theme-color" media="(prefers-color-scheme: light)" content="#f6f5f1">
<meta name="theme-color" media="(prefers-color-scheme: dark)" content="#15171a">
<link rel="manifest" href="../manifest.webmanifest">
<link rel="icon" type="image/png" href="../icons/icon-192.png">
<link rel="apple-touch-icon" href="../icons/apple-touch-icon.png">
<style>${CSS}</style>
</head>
<body>
<div class="wrap">
<header class="site">
  <h1>📚 過去のダイジェスト</h1>
  <nav class="links"><a href="../index.html">← 最新のダイジェストへ</a></nav>
</header>
<ul class="arch">
${lis}
</ul>
</div>
</body>
</html>`;
}

export function renderSite(data, docsDir) {
  const dataDir = path.join(docsDir, 'data');
  const archiveDir = path.join(docsDir, 'archive');
  fs.mkdirSync(dataDir, { recursive: true });
  fs.mkdirSync(archiveDir, { recursive: true });

  // PWA用の静的アセット(manifest / service worker / アイコン)をコピー
  const staticDir = path.resolve(docsDir, '..', 'static');
  if (fs.existsSync(staticDir)) fs.cpSync(staticDir, docsDir, { recursive: true });

  fs.writeFileSync(path.join(dataDir, `${data.date}.json`), JSON.stringify(data, null, 1));
  fs.writeFileSync(path.join(dataDir, 'latest.json'), JSON.stringify(data, null, 1));
  fs.writeFileSync(path.join(docsDir, '.nojekyll'), '');

  // 利用可能な日付一覧(昇順)。アプリ用の目録 data/index.json もここで出力する
  const dates = fs
    .readdirSync(dataDir)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.json$/.test(f))
    .map((f) => f.replace('.json', ''))
    .sort();
  const byDate = new Map(
    dates.map((d) => [d, JSON.parse(fs.readFileSync(path.join(dataDir, `${d}.json`), 'utf8'))]),
  );
  fs.writeFileSync(
    path.join(dataDir, 'index.json'),
    JSON.stringify({ dates: [...dates].reverse() }, null, 1),
  );

  // 全アーカイブページを毎回再生成する(前日/翌日ナビを常に最新に保つため)
  dates.forEach((d, i) => {
    fs.writeFileSync(
      path.join(archiveDir, `${d}.html`),
      renderPage(byDate.get(d), {
        isArchive: true,
        prevDate: i > 0 ? dates[i - 1] : null,
        nextDate: i < dates.length - 1 ? dates[i + 1] : null,
      }),
    );
  });

  // 最新ページ(今日)には前日リンクだけ付ける
  fs.writeFileSync(
    path.join(docsDir, 'index.html'),
    renderPage(data, { prevDate: dates.length > 1 ? dates[dates.length - 2] : null }),
  );

  // 日付一覧(新しい順・トップ3見出し付き)
  const entries = [...dates].reverse().map((d) => ({
    date: d,
    headlines: (byDate.get(d).topics || []).slice(0, 3).map((t) => t.headline),
  }));
  fs.writeFileSync(path.join(archiveDir, 'index.html'), renderArchiveIndex(entries));

  const recent = [...dates].reverse().slice(0, 20).map((d) => byDate.get(d));
  fs.writeFileSync(path.join(docsDir, 'feed.xml'), renderFeedXml(recent));
}
