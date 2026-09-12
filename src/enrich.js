// Additive v2 fields: the public website and older apps keep using summary/topics.
import { createHash } from 'node:crypto';

export const TOPIC_LABELS = ['モデル・API', 'エージェント', '画像・動画生成', '音声', '企業導入事例', '規制・政策', '研究・論文', '開発ツール', '国内動向', '資金調達・M&A'];
export const stableID = (url) => createHash('sha256').update(url).digest('hex').slice(0, 24);
export const safeURL = (value) => {
  try { const u = new URL(value); return /^https?:$/.test(u.protocol) ? u.href : null; } catch { return null; }
};
export function classify(text) {
  const rules = [/model|モデル|API|GPT|Claude|Gemini/i, /agent|エージェント/i, /image|video|画像|動画/i, /audio|speech|voice|音声/i, /企業|導入|enterprise/i, /regulat|policy|規制|法案|政策/i, /research|paper|研究|論文/i, /開発|code|coding|SDK|tool/i, /日本|国内|Japan/i, /funding|acquisit|資金|買収/i];
  const labels = TOPIC_LABELS.filter((_, i) => rules[i].test(text));
  return labels.length ? labels.slice(0, 3) : ['モデル・API'];
}
export function enrichSummary(hit, cluster, fallback) {
  const text = (value, limit) => typeof value === 'string' ? value.trim().slice(0, limit) : '';
  if (!hit || !text(hit.headline, 200) || !text(hit.summary, 1200)) return { ...fallback, aiGenerated: false, topics: classify(cluster.representative.title) };
  const labels = Array.isArray(hit.topics) ? hit.topics.filter(t => TOPIC_LABELS.includes(t)) : [];
  const styles = hit.summaryStyles || {};
  const faq = (Array.isArray(hit.faq) ? hit.faq : []).filter(f => typeof f?.q === 'string' && typeof f?.a === 'string').slice(0, 3).map(f => ({ q: text(f.q, 200), a: text(f.a, 800) }));
  return {
    headline: text(hit.headline, 200), summary: text(hit.summary, 1200), whyItMatters: text(hit.whyItMatters, 600),
    aiGenerated: true, topics: [...new Set(labels)].slice(0, 3).length ? [...new Set(labels)].slice(0, 3) : classify(hit.headline),
    summaryStyles: { short: text(styles.short, 600) || hit.summary, detail: text(styles.detail, 1600) || hit.summary, simple: text(styles.simple, 1000) || hit.summary },
    ttsText: text(hit.ttsText, 1800) || `${hit.headline}。${hit.summary}`,
    faq, socialPost: text(hit.socialPost, 160),
  };
}

// Conservative bound (all non-ASCII count twice). Native editor provides the
// weighted count including emoji and URL handling. Never append invented facts.
function fit(text, budget = 245) {
  let result = '', used = 0;
  for (const c of text.normalize('NFC')) {
    const weight = c.codePointAt(0) <= 0x10ff ? 1 : 2;
    if (used + weight > budget - 2) return `${result}…`;
    result += c; used += weight;
  }
  return result;
}
export function createDrafts(topics, date) {
  const eligible = topics.filter(t => safeURL(t.articles?.[0]?.link));
  if (!eligible.length) return [];
  const drafts = [];
  const labels = ['AIニュース', '今日の注目', '朝のAIメモ', 'AI動向まとめ', 'チェックしたい発表', '今日のAIトピック', 'AIニュース備忘録', '注目ニュースの要点', 'AIニュースを読む', '朝のキャッチアップ'];
  for (let i = 0; i < 10; i++) {
    const t = eligible[i % eligible.length];
    const variant = Math.floor(i / eligible.length);
    const label = labels[variant % labels.length];
    const source = safeURL(t.articles[0].link);
    const body = variant === 0 && t.socialPost ? t.socialPost : `${t.headline}\n${variant % 2 ? (t.whyItMatters || t.summary) : t.summary}`;
    const text = `${fit(`【${label}】\n${body}`)}\n${source}\n#生成AI`;
    drafts.push({ id: `${date}-${t.id || stableID(source)}-${variant}`, title: `${i + 1}. ${t.headline}`, text, sourceIDs: [t.id || stableID(source)], sourceURLs: [source], aiGenerated: Boolean(t.aiGenerated && variant === 0 && t.socialPost) });
  }
  for (let group = 0; group < 2; group++) {
    const selected = eligible.slice(group * 3, group * 3 + 3);
    if (selected.length < 3) continue;
    const sourceURLs = selected.map(t => safeURL(t.articles[0].link));
    const label = group === 0 ? 'AIニュース3選' : 'あわせて読みたいAIニュース';
    const text = `【${label}】\n${selected.map((t, i) => `${fit(t.headline, 45)}\n${sourceURLs[i]}`).join('\n')}\n#生成AI`;
    drafts[8 + group] = { id: `${date}-roundup-${stableID(sourceURLs.join('\n'))}`, title: `${9 + group}. ${label}`, text, sourceIDs: selected.map(t => t.id || stableID(t.articles[0].link)), sourceURLs, aiGenerated: false };
  }
  return drafts;
}
