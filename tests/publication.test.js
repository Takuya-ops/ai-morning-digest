import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { initializePublication, completePublication, contentRevision, waveInfo, digestHash } from '../src/publication.js';
import { GEMINI_VOICE, speechText } from '../src/speech.js';
import { renderPage } from '../src/render.js';
const wav = fs.readFileSync(new URL('../ios/AIDigest/Resources/gemini-preview.wav', import.meta.url));
const sample = () => ({ date: '2026-10-04', generatedAt: '2026-10-04T00:00:00Z', since: '2026-10-03T00:00:00Z', topics: [{ headline: '音声ニュース', summary: '日本語の本文です。', ttsText: '日本語です。 https://example.com', aiGenerated: true, articles: [{ link: 'https://example.com', lang: 'ja' }], rank: 1 }], others: [], stats: { feedErrors: [] } });
test('publication transitions preserve text revision and add verified audio metadata', async () => {
  const data = sample(); initializePublication(data, GEMINI_VOICE, true);
  const revision = data.publication.contentRevision;
  assert.equal(data.publication.audioByVoice[GEMINI_VOICE].state, 'pending');
  assert.equal(data.topics[0].narration.scriptHash, digestHash(speechText(data.topics[0])));
  data.topics[0].audio = { [GEMINI_VOICE]: 'https://github.com/Takuya-ops/ai-morning-digest/releases/download/test/test.wav' };
  assert.equal(await completePublication(data, GEMINI_VOICE, { fetcher: async () => new Response(wav) }), 'ready');
  assert.equal(data.publication.contentRevision, revision); assert.equal(contentRevision(data), revision);
  assert.ok(data.topics[0].audioMetadata[GEMINI_VOICE].durationSeconds > 15);
  assert.equal(data.topics[0].audioMetadata[GEMINI_VOICE].byteLength, wav.length);
});
test('failed audio retains text and does not expose partial audio URLs', async () => {
  const data = sample(); data.topics.push(structuredClone(data.topics[0])); initializePublication(data, GEMINI_VOICE, true);
  data.topics[0].audio = { [GEMINI_VOICE]: 'https://github.com/Takuya-ops/ai-morning-digest/releases/download/test/test.wav' };
  assert.equal(await completePublication(data, GEMINI_VOICE, { fetcher: async () => new Response(wav) }), 'failed');
  assert.ok(data.topics.every(t => !t.audio?.[GEMINI_VOICE])); assert.equal(data.topics[0].summary, '日本語の本文です。');
});
test('missing key reports unavailable and malformed WAV is rejected', async () => {
  const data = sample(); initializePublication(data, GEMINI_VOICE, false);
  assert.equal(await completePublication(data, GEMINI_VOICE), 'unavailable');
  assert.throws(() => waveInfo(wav.subarray(0, 100))); assert.throws(() => waveInfo(Buffer.from('<html>error</html>')));
});
test('web never exposes playback even when an archive contains old audio URLs', () => {
  const data = sample(); data.topics[0].audio = { [GEMINI_VOICE]: 'https://github.com/Takuya-ops/ai-morning-digest/releases/download/test/test.wav' };
  const html = renderPage(data);
  assert.ok(!html.includes('<audio')); assert.ok(!html.includes('briefing-player')); assert.ok(!html.includes('test.wav'));
});

test('Gemini summary uses a server-side key, and API failures preserve source excerpts', async () => {
  const { summarizeTopics } = await import('../src/summarize.js');
  const before = { fetch: globalThis.fetch, gemini: process.env.GEMINI_API_KEY, anthropic: process.env.ANTHROPIC_API_KEY };
  const source = { title: 'Original English announcement', summary: 'This is an original source excerpt with enough factual detail to be retained.', lang: 'en', feedName: 'Source' };
  const clusters = [{ representative: source, members: [source] }];
  try {
    delete process.env.ANTHROPIC_API_KEY; process.env.GEMINI_API_KEY = 'test-only';
    globalThis.fetch = async (url, request) => {
      assert.ok(url.includes('generativelanguage.googleapis.com')); assert.equal(request.headers['x-goog-api-key'], 'test-only');
      return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: JSON.stringify([{ index: 0, headline: '日本語の見出し', summary: '日本語で要約しました。', summaryStyles: { short: '短文です。' } }]) }] } }] });
    };
    const result = await summarizeTopics(clusters); assert.equal(result[0].aiGenerated, true); assert.equal(result[0].summaryStyles.detail, null);
    globalThis.fetch = async () => new Response('', { status: 403 });
    const failed = await summarizeTopics(clusters); assert.equal(failed[0].aiGenerated, false); assert.equal(failed[0].summary, source.summary); assert.equal(failed[0].faq, undefined);
  } finally {
    globalThis.fetch = before.fetch;
    for (const [name, value] of [['GEMINI_API_KEY', before.gemini], ['ANTHROPIC_API_KEY', before.anthropic]]) { if (value === undefined) delete process.env[name]; else process.env[name] = value; }
  }
});

test('an English excerpt with a Japanese fallback message is not a Japanese narration', () => {
  const data = sample(); Object.assign(data.topics[0], { headline: 'English headline', summary: '要約情報なし。', ttsText: null, aiGenerated: false, articles: [{ link: 'https://example.com', lang: 'en' }] });
  initializePublication(data, GEMINI_VOICE, false);
  assert.equal(data.topics[0].narration.language, 'en'); assert.equal(data.topics[0].editorial.status, 'untranslated');
});

test('summary retries transient errors and falls back to the available stable model', async () => {
  const { geminiSummaryResponse } = await import('../src/summarize.js'); let calls = 0, waits = 0;
  const result = await geminiSummaryResponse('test', { key: 'test', wait: async () => { waits++; }, fetcher: async url => {
    calls++; if (url.includes('gemini-3.8-flash')) return new Response('', { status: 503 });
    return Response.json({ candidates: [{ finishReason: 'STOP', content: { parts: [{ text: '[{"index":0,"summary":"日本語です。"}]' }] } }] });
  } });
  assert.equal(calls, 4); assert.equal(waits, 2); assert.equal(result.model, 'gemini-2.5-flash');
});
