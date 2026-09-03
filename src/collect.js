import Parser from 'rss-parser';
import { FEEDS } from './feeds.js';
import { isAiRelated } from './keywords.js';

const parser = new Parser({
  timeout: 25000,
  headers: {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ai-morning-digest/1.0',
    Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
  },
  customFields: {
    item: [
      ['dc:date', 'dcDate'],
      ['content:encoded', 'contentEncoded'],
    ],
  },
});

function stripHtml(html) {
  if (!html) return '';
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#0?39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function itemDate(item) {
  for (const v of [item.isoDate, item.pubDate, item.dcDate]) {
    if (!v) continue;
    const d = new Date(v);
    if (!Number.isNaN(d.getTime())) return d;
  }
  return null;
}

function itemSummary(item) {
  const raw =
    item.contentSnippet || stripHtml(item.contentEncoded) || stripHtml(item.content) ||
    stripHtml(item.summary) || stripHtml(item.description) || '';
  return raw.replace(/\s+/g, ' ').trim().slice(0, 1200);
}

// rss-parser自体のtimeoutが効かないケース(接続がハングする等)に備えたハードタイムアウト
function withHardTimeout(promise, ms, label) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`hard timeout after ${ms}ms (${label})`)), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}

async function fetchFeed(feed, since) {
  const parsed = await withHardTimeout(parser.parseURL(feed.url), 45000, feed.id);
  const items = [];
  for (const item of (parsed.items || []).slice(0, 120)) {
    const date = itemDate(item);
    if (!date || date < since || date.getTime() > Date.now() + 60 * 60 * 1000) continue;
    const title = (item.title || '').replace(/\s+/g, ' ').trim();
    const link = (item.link || '').trim();
    if (!title || !link) continue;
    const summary = itemSummary(item);
    if (!feed.aiOnly && !isAiRelated(`${title} ${summary}`)) continue;
    items.push({
      feedId: feed.id,
      feedName: feed.name,
      weight: feed.weight,
      lang: feed.lang,
      title,
      link,
      date: date.toISOString(),
      summary,
    });
  }
  return items;
}

// 全フィードを並列取得。失敗したフィードはエラーとして記録し、残りで続行する。
export async function collectArticles(windowHours) {
  const since = new Date(Date.now() - windowHours * 60 * 60 * 1000);
  const results = await Promise.allSettled(FEEDS.map((f) => fetchFeed(f, since)));

  const articles = [];
  const feedErrors = [];
  results.forEach((res, i) => {
    if (res.status === 'fulfilled') {
      articles.push(...res.value);
    } else {
      feedErrors.push({ feedId: FEEDS[i].id, feedName: FEEDS[i].name, error: String(res.reason?.message || res.reason) });
    }
  });

  // URL重複を除去(同一記事が複数フィードに載る場合は高ウェイト側を残す)
  const byLink = new Map();
  for (const a of articles) {
    const key = a.link.replace(/[?#].*$/, '');
    const prev = byLink.get(key);
    if (!prev || a.weight > prev.weight) byLink.set(key, a);
  }

  return {
    since: since.toISOString(),
    articles: [...byLink.values()].sort((a, b) => new Date(b.date) - new Date(a.date)),
    feedErrors,
    feedCount: FEEDS.length,
  };
}
