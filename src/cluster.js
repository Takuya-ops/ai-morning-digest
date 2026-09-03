import { extractEntities } from './keywords.js';

const STOPWORDS = new Set([
  'the', 'a', 'an', 'to', 'of', 'for', 'and', 'with', 'in', 'on', 'at', 'is', 'are', 'was', 'be',
  'as', 'by', 'it', 'its', 'this', 'that', 'from', 'new', 'how', 'why', 'what', 'will', 'can',
  'has', 'have', 'had', 'said', 'says', 'say', 'more', 'about', 'after', 'into', 'over', 'their',
  'they', 'you', 'your', 'we', 'our', 'us', 'using', 'use', 'uses', 'vs', 'via', 'not', 'no',
  'up', 'out', 'all', 'now', 'but', 'or', 'if', 'so', 'my', 'me', 'do', 'does', 'get', 'gets',
  'announces', 'announced', 'launches', 'launched', 'releases', 'released', 'reveals', 'report',
  'reportedly', 'show', 'hn', 'ask', 'first', 'just', 'here', 'when', 'where', 'than', 'then',
  '発表', '公開', '提供', '開始', '対応', '向け', '搭載', '活用', '登場', '発売', '最新',
  '記事', 'ニュース', '可能', '開発', '実現', '解説', '紹介', '説明', '今日', '本日', '発表会',
]);

// 企業名はニュース全般に頻出しトピックの中身を表さないため、内容類似度の計算からは除外する
// (Gemini・Sora等の製品名は内容トークンとして残す)
const COMPANY_TOKENS = new Set([
  'google', 'openai', 'anthropic', 'microsoft', 'meta', 'nvidia', 'apple', 'amazon', 'aws',
  'deepmind', 'xai', 'alibaba', 'softbank', 'sakana', 'rakuten', 'ntt', 'fujitsu', 'nec',
  'sony', 'samsung', 'intel', 'amd', 'tsmc', 'oracle', 'salesforce', 'adobe', 'tesla',
  'stability', 'huggingface', 'hugging', 'mistral', 'perplexity', 'github',
  'グーグル', 'マイクロソフト', 'アップル', 'アマゾン', 'エヌビディア', 'ソフトバンク',
  '富士通', 'ソニー', 'サムスン', 'インテル', 'オラクル', 'アドビ', 'テスラ', '楽天',
]);

// タイトルからトークン集合を作る。
// 英数字の連続 + カタカナ/漢字の連続(ひらがな=助詞で自然に区切る)を語とみなす。
export function tokenize(text) {
  const normalized = text.normalize('NFKC').toLowerCase();
  const tokens = new Set();
  for (const m of normalized.matchAll(/[a-z0-9][a-z0-9.+\-]*/g)) {
    const t = m[0].replace(/[.\-]+$/, '');
    if (t.length >= 2 && !STOPWORDS.has(t) && !/^\d{1,4}$/.test(t)) tokens.add(t);
  }
  for (const m of normalized.matchAll(/[゠-ヿ一-鿿々ー]{2,}/g)) {
    const t = m[0];
    if (!STOPWORDS.has(t)) tokens.add(t);
  }
  return tokens;
}

function contentTokens(tokens) {
  return new Set([...tokens].filter((t) => !COMPANY_TOKENS.has(t)));
}

function intersection(a, b) {
  const out = [];
  for (const t of a) if (b.has(t)) out.push(t);
  return out;
}

// 記事ペアが同一トピックかどうかの判定。
// エンティティ(固有名)の一致 + 企業名を除いた内容トークンの重なりで判定することで、
// 「Google×Gemini」のような頻出組み合わせだけによる誤結合を防ぐ。
function pairScore(a, b) {
  const sharedEnt = intersection(a.entities, b.entities).length;
  const inter = intersection(a.content, b.content).length;
  const minSize = Math.max(1, Math.min(a.content.size, b.content.size));
  const containment = inter / minSize;
  const match =
    inter >= 2 &&
    ((sharedEnt >= 1 && containment >= 0.5) ||
      (sharedEnt >= 2 && containment >= 0.4) ||
      containment >= 0.7);
  return match ? sharedEnt + containment * 3 : 0;
}

function makeSig(article) {
  const text = `${article.title} ${article.summary.slice(0, 200)}`;
  const tokens = tokenize(article.title);
  return {
    article,
    entities: extractEntities(text),
    tokens,
    content: contentTokens(tokens),
  };
}

// 単リンク法クラスタリング: 記事ペア同士で比較する(クラスタの和集合と比較すると
// クラスタが育つほど類似度が薄まり、同一トピックが分裂するため)。
export function clusterArticles(articles) {
  const sigs = articles.map(makeSig);
  sigs.sort((x, y) => y.article.weight - x.article.weight || new Date(y.article.date) - new Date(x.article.date));

  const clusters = [];
  for (const sig of sigs) {
    let best = null;
    let bestScore = 0;
    for (const c of clusters) {
      for (const member of c.sigs) {
        const score = pairScore(sig, member);
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
    }
    if (best) best.sigs.push(sig);
    else clusters.push({ sigs: [sig] });
  }

  // 仕上げのマージパス: 別々に育ったクラスタ同士でもペアが一致すれば統合する
  let merged = true;
  while (merged) {
    merged = false;
    outer: for (let i = 0; i < clusters.length; i++) {
      for (let j = i + 1; j < clusters.length; j++) {
        for (const a of clusters[i].sigs) {
          for (const b of clusters[j].sigs) {
            if (pairScore(a, b) > 0) {
              clusters[i].sigs.push(...clusters[j].sigs);
              clusters.splice(j, 1);
              merged = true;
              break outer;
            }
          }
        }
      }
    }
  }
  return clusters;
}

// トピックの「大きさ」= 報じている独立ソースの重みの合計を軸にスコア化
export function rankClusters(clusters) {
  const ranked = clusters.map((c) => {
    const members = c.sigs.map((s) => s.article);
    const byFeed = new Map();
    for (const m of members) {
      const prev = byFeed.get(m.feedId);
      if (!prev || m.weight > prev.weight) byFeed.set(m.feedId, m);
    }
    const distinct = [...byFeed.values()];
    const weightSum = distinct.reduce((s, m) => s + m.weight, 0);
    const sourceBonus = (distinct.length - 1) * 1.5;
    const langs = new Set(distinct.map((m) => m.lang));
    const crossLangBonus = langs.size > 1 ? 1.5 : 0;
    const newest = Math.max(...members.map((m) => new Date(m.date).getTime()));
    const recencyBonus = Date.now() - newest < 12 * 60 * 60 * 1000 ? 0.5 : 0;
    const score = weightSum + sourceBonus + crossLangBonus + recencyBonus;

    // 代表記事: クラスタ内で最も「中心的」な記事(他メンバーと内容トークンを多く共有)を選ぶ。
    // 同点なら日本語 > 高ウェイト > 新しい順(表示タイトルの読みやすさのため)。
    const centrality = new Map();
    for (const s of c.sigs) {
      let total = 0;
      for (const other of c.sigs) {
        if (other !== s) total += intersection(s.content, other.content).length;
      }
      centrality.set(s.article, total);
    }
    const sorted = [...members].sort(
      (a, b) =>
        centrality.get(b) - centrality.get(a) ||
        (b.lang === 'ja') - (a.lang === 'ja') ||
        b.weight - a.weight ||
        new Date(b.date) - new Date(a.date),
    );
    const entities = new Set();
    for (const s of c.sigs) for (const e of s.entities) entities.add(e);
    return {
      score: Math.round(score * 10) / 10,
      sourceCount: distinct.length,
      representative: sorted[0],
      members: [...members].sort((a, b) => b.weight - a.weight || new Date(b.date) - new Date(a.date)),
      entities: [...entities],
    };
  });
  ranked.sort((a, b) => b.score - a.score || new Date(b.representative.date) - new Date(a.representative.date));
  return ranked;
}
