import test from 'node:test';
import assert from 'node:assert/strict';
import { classify, createDrafts, enrichSummary, safeURL, stableID } from '../src/enrich.js';
import { fallbackSummary } from '../src/summarize.js';

const cluster = { representative: { title: '新しい音声モデル', link: 'https://example.com/audio', summary: '記事に記載された音声モデルの具体的な改善内容です。'.repeat(3) }, members: [] };
cluster.members = [cluster.representative];
const topic = { id: stableID(cluster.representative.link), headline: cluster.representative.title, summary: cluster.representative.summary, articles: [cluster.representative] };
test('ten traceable drafts, stable IDs, no fabricated extra sources', () => {
  const drafts = createDrafts([topic], '2026-09-12');
  assert.equal(drafts.length, 10);
  assert.equal(new Set(drafts.map(d => d.id)).size, 10);
  for (const draft of drafts) { assert.deepEqual(draft.sourceURLs, ['https://example.com/audio']); assert.ok(draft.text.includes('https://example.com/audio')); }
  assert.deepEqual(createDrafts([topic], '2026-09-12'), drafts);
});
test('empty input and unsafe source never produce drafts', () => {
  assert.deepEqual(createDrafts([], '2026-09-12'), []);
  assert.deepEqual(createDrafts([{ ...topic, articles: [{ link: 'javascript:alert(1)' }] }], '2026-09-12'), []);
  assert.equal(safeURL('file:///etc/passwd'), null);
});
test('generated fields reject malformed types and invalid labels', () => {
  const result = enrichSummary({ headline: '音声モデル', summary: '要約', topics: ['bad', '音声', '音声'], faq: [{ q: '質問', a: '記事には記載なし' }, { q: 3, a: '不正' }], summaryStyles: { detail: 99 } }, cluster, fallbackSummary(cluster));
  assert.deepEqual(result.topics, ['音声']); assert.equal(result.faq.length, 1); assert.equal(result.summaryStyles.detail, '要約'); assert.equal(result.aiGenerated, true);
});
test('fallback does not pretend styles and FAQ were AI generated', () => {
  const result = enrichSummary(null, cluster, fallbackSummary(cluster));
  assert.equal(result.aiGenerated, false); assert.equal(result.summaryStyles, undefined); assert.equal(result.faq, undefined);
  assert.ok(classify('音声モデルAPI').includes('音声'));
});
test('long Japanese copy has a conservative X length within 280', () => {
  for (const draft of createDrafts([{ ...topic, summary: '日本語の長い記事。'.repeat(100) }], '2026-09-12')) {
    const normalized = draft.text.replace(/https:\/\/example.com\/audio/g, 'a'.repeat(23));
    const weight = [...normalized].reduce((sum, c) => sum + (c.codePointAt(0) <= 0x10ff ? 1 : 2), 0);
    assert.ok(weight <= 280, String(weight));
  }
});
test('roundup alternatives retain all three source links', () => {
  const topics = Array.from({ length: 10 }, (_, i) => ({ ...topic, id: `id-${i}`, headline: 'とても長い日本語のニュース見出し'.repeat(10), articles: [{ link: `https://example.com/${i}` }] }));
  const drafts = createDrafts(topics, '2026-09-12');
  assert.equal(drafts.length, 10);
  for (const d of drafts.slice(8)) {
    assert.equal(d.sourceURLs.length, 3);
    for (const url of d.sourceURLs) assert.ok(d.text.includes(url));
    const normalized = d.text.replace(/https:\/\/example.com\/\d/g, 'a'.repeat(23));
    assert.ok([...normalized].reduce((n, c) => n + (c.codePointAt(0) <= 0x10ff ? 1 : 2), 0) <= 280);
  }
});
