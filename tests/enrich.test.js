import test from 'node:test';
import assert from 'node:assert/strict';
import { classify, enrichSummary, safeURL, stableID } from '../src/enrich.js';
import { fallbackSummary } from '../src/summarize.js';

const cluster = { representative: { title: '新しい音声モデル', link: 'https://example.com/audio', summary: '記事に記載された音声モデルの具体的な改善内容です。'.repeat(3) }, members: [] };
cluster.members = [cluster.representative];
const topic = { id: stableID(cluster.representative.link), headline: cluster.representative.title, summary: cluster.representative.summary, articles: [cluster.representative] };
test('generated fields reject malformed types and invalid labels', () => {
  const result = enrichSummary({ headline: '音声モデル', summary: '要約', topics: ['bad', '音声', '音声'], faq: [{ q: '質問', a: '記事には記載なし' }, { q: 3, a: '不正' }], summaryStyles: { detail: 99 } }, cluster, fallbackSummary(cluster));
  assert.deepEqual(result.topics, ['音声']); assert.equal(result.faq.length, 1); assert.equal(result.summaryStyles.detail, null); assert.equal(result.aiGenerated, true);
});
test('partial generated styles preserve line breaks without copying a fallback into missing styles', () => {
  const short = '新しいモデルが登場。\n音声の認識を改善。\n提供地域は記載なし。';
  const result = enrichSummary({ headline: '音声モデル', summary: '既存の要約', summaryStyles: { short, detail: '  ', simple: null } }, cluster, fallbackSummary(cluster));
  assert.deepEqual(result.summaryStyles, { short, detail: null, simple: null });
  assert.equal(result.summary, '既存の要約');
});
test('fallback does not pretend styles and FAQ were AI generated', () => {
  const result = enrichSummary(null, cluster, fallbackSummary(cluster));
  assert.equal(result.aiGenerated, false); assert.equal(result.summaryStyles, undefined); assert.equal(result.faq, undefined);
  assert.ok(classify('音声モデルAPI').includes('音声'));
});
