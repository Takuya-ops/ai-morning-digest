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
    // A missing style must stay unavailable; copying summary made the picker
    // appear functional while every option displayed exactly the same text.
    summaryStyles: { short: text(styles.short, 600) || null, detail: text(styles.detail, 1600) || null, simple: text(styles.simple, 1000) || null },
    ttsText: text(hit.ttsText, 1800) || `${hit.headline}。${hit.summary}`,
    faq,
  };
}
