import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectArticles } from './collect.js';
import { clusterArticles, rankClusters } from './cluster.js';
import { summarizeTopics, fallbackSummary } from './summarize.js';
import { renderSite, toJstYmd } from './render.js';
import { notifySlack } from './notify.js';

const TOP_N = Number(process.env.DIGEST_TOP_N || 10);
const WINDOW_HOURS = Number(process.env.DIGEST_WINDOW_HOURS || 26);
const SITE_URL = process.env.SITE_URL || 'https://takuya-ops.github.io/ai-morning-digest';

const here = path.dirname(fileURLToPath(import.meta.url));
const docsDir = path.resolve(here, '..', 'docs');

async function main() {
  console.log(`collect: 過去${WINDOW_HOURS}時間の記事を収集します...`);
  const { since, articles, feedErrors, feedCount } = await collectArticles(WINDOW_HOURS);
  console.log(`collect: ${articles.length}件の生成AI関連記事を取得 (取得失敗: ${feedErrors.length}フィード)`);
  for (const e of feedErrors) console.warn(`  ⚠️ ${e.feedName}: ${e.error}`);

  const clusters = rankClusters(clusterArticles(articles));
  console.log(`cluster: ${clusters.length}トピックに集約`);

  const top = clusters.slice(0, TOP_N);
  const rest = clusters.slice(TOP_N);

  console.log(`summarize: 上位${top.length}トピックを要約します...`);
  const summaries = await summarizeTopics(top);

  const topics = top.map((c, i) => {
    const s = summaries[i] || fallbackSummary(c);
    // 見出し・要約の元になった代表記事を先頭に置く(render/notifyはarticles[0]をリンク先に使う)
    const ordered = [c.representative, ...c.members.filter((m) => m !== c.representative)];
    return {
      rank: i + 1,
      headline: s.headline,
      summary: s.summary,
      whyItMatters: s.whyItMatters,
      score: c.score,
      sourceCount: c.sourceCount,
      entities: c.entities,
      articles: ordered.map((m) => ({
        title: m.title, link: m.link, feedName: m.feedName, lang: m.lang, date: m.date,
      })),
    };
  });

  // TOP10に入らなかった記事もすべて掲載する(抜け漏れ防止)
  const others = rest
    .flatMap((c) => c.members)
    .sort((a, b) => new Date(b.date) - new Date(a.date))
    .map((m) => ({ title: m.title, link: m.link, feedName: m.feedName, lang: m.lang, date: m.date }));

  const generatedAt = new Date().toISOString();
  const data = {
    date: toJstYmd(generatedAt),
    generatedAt,
    since,
    windowHours: WINDOW_HOURS,
    stats: {
      articleCount: articles.length,
      feedCount,
      topicCount: clusters.length,
      feedErrors,
    },
    topics,
    others,
  };

  renderSite(data, docsDir);
  console.log(`render: ${docsDir} にHTML/JSON/RSSを出力しました (${data.date})`);

  await notifySlack(data, SITE_URL).catch((err) => console.warn(`notify: ${err.message}`));

  console.log('--- 本日のTOPトピック ---');
  for (const t of topics) console.log(`${t.rank}. [${t.sourceCount}ソース] ${t.headline}`);
}

main()
  .then(() => process.exit(0)) // ハングしたソケットが残ってもプロセスを確実に終了させる
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
