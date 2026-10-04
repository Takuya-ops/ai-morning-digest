import test from 'node:test';
import assert from 'node:assert/strict';
import { synthesize, attachMicrosoftAudio, assetName, releasePublisher, MICROSOFT_VOICES } from '../src/speech.js';

const quiet = { info() {}, warn() {} };
const env = { AZURE_SPEECH_KEY: 'test-only', AZURE_SPEECH_REGION: 'japaneast' };
const topic = () => ({ headline: 'AIニュース', summary: '公開された情報です。', ttsText: 'ニュースの読み上げです。' });
test('Microsoft voice list always includes Nanami; SSML is escaped and only official regional host receives key', async () => {
  assert.ok(MICROSOFT_VOICES.includes('ja-JP-NanamiNeural'));
  let seen;
  const bytes = await synthesize('A&B <voice name="other">', MICROSOFT_VOICES[0], { key: 'test-only', region: 'japaneast', fetcher: async (url, request) => {
    seen = { url, request }; return new Response(new Uint8Array(600), { status: 200 });
  } });
  assert.equal(bytes.length, 600);
  assert.equal(seen.url, 'https://japaneast.tts.speech.microsoft.com/cognitiveservices/v1');
  assert.match(seen.request.body, /A&amp;B &lt;voice name=&quot;other&quot;&gt;/);
  assert.equal(seen.request.headers['X-Microsoft-OutputFormat'], 'audio-24khz-48kbitrate-mono-mp3');
  assert.equal(seen.request.redirect, 'error');
  await assert.rejects(synthesize('x', 'injected"voice', { key: 'x', region: 'japaneast' }));
  await assert.rejects(synthesize('x', MICROSOFT_VOICES[0], { key: 'x', region: 'evil.example/' }));
});
test('missing keys make no network calls; reruns reuse audio and do not synthesize twice', async () => {
  const data = { date: '2026-09-12', topics: [topic()] };
  const forbidden = async () => { throw new Error('Unexpected network'); };
  await attachMicrosoftAudio(data, { env: {}, fetcher: forbidden, log: quiet });
  assert.equal(data.topics[0].audio, undefined);
  const saved = new Map(); let calls = 0;
  const publisher = { existing: (name) => saved.get(name), upload: async (name) => { const url = `https://github.com/owner/repo/releases/download/day/${name}`; saved.set(name, url); return url; } };
  const synth = async () => { calls++; return Buffer.alloc(600); };
  await attachMicrosoftAudio(data, { env, publisher, synth, log: quiet });
  assert.equal(Object.keys(data.topics[0].audio).length, 2); assert.equal(calls, 2);
  await attachMicrosoftAudio(data, { env, publisher, synth, log: quiet });
  assert.equal(calls, 2);
  assert.notEqual(assetName(topic(), MICROSOFT_VOICES[0]), assetName({ ...topic(), ttsText: '変更したニュース' }, MICROSOFT_VOICES[0]));
});
test('partially generated voice is not advertised; other voice can still complete', async () => {
  const data = { date: '2026-09-12', topics: [topic(), { ...topic(), ttsText: '2件目' }] };
  const publisher = { existing: () => null, upload: async (name) => `https://example.com/${name}` };
  await attachMicrosoftAudio(data, { env, publisher, log: quiet, synth: async (text, voice) => {
    if (text === '2件目' && voice === MICROSOFT_VOICES[0]) throw new Error('Service unavailable');
    return Buffer.alloc(600);
  } });
  assert.ok(data.topics.every(t => !t.audio[MICROSOFT_VOICES[0]] && t.audio[MICROSOFT_VOICES[1]]));
});
test('release assets use fixed GitHub hosts and changed-voice assets are reusable', async () => {
  const requests = [];
  const repository = 'owner/repo';
  const url = 'https://github.com/owner/repo/releases/download/digest-audio-2026-09-12/audio.mp3';
  const publisher = await releasePublisher({ repository, token: 'test-only', date: '2026-09-12', fetcher: async (target, request) => {
    requests.push({ target, request });
    if (target.includes('/tags/')) return new Response('{}', { status: 404 });
    if (target.endsWith('/releases')) return Response.json({ id: 42, upload_url: 'https://untrusted.example/upload' });
    if (target.includes('per_page')) return Response.json([{ name: 'existing.mp3', state: 'uploaded', size: 600, browser_download_url: url }]);
    return Response.json({ browser_download_url: url });
  } });
  assert.equal(publisher.existing('existing.mp3'), url);
  assert.equal(await publisher.upload('audio.mp3', Buffer.alloc(600)), url);
  assert.ok(requests.every(({ target, request }) => ['api.github.com', 'uploads.github.com'].includes(new URL(target).hostname) && request.redirect === 'error'));
  const created = JSON.parse(requests.find(r => r.target.endsWith('/releases')).request.body);
  assert.equal(created.make_latest, 'false');
});

// Gemini 3.8 returns WAV, not the raw PCM returned by earlier TTS models.
const { GEMINI_MODEL, GEMINI_VOICE, GEMINI_STYLE, synthesizeGemini, attachGeminiAudio, geminiAssetName } = await import('../src/speech.js');
function wav() {
  const bytes = Buffer.alloc(1004);
  bytes.write('RIFF'); bytes.writeUInt32LE(bytes.length - 8, 4); bytes.write('WAVE', 8);
  bytes.write('fmt ', 12); bytes.writeUInt32LE(16, 16); bytes.writeUInt16LE(1, 20); bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(24000, 24); bytes.writeUInt32LE(48000, 28); bytes.writeUInt16LE(2, 32); bytes.writeUInt16LE(16, 34);
  bytes.write('data', 36); bytes.writeUInt32LE(960, 40);
  return bytes;
}
const geminiResponse = (bytes = wav(), mimeType = 'audio/wav', finishReason = 'STOP') => Response.json({ candidates: [{ finishReason, content: { parts: [{ inlineData: { mimeType, data: bytes.toString('base64') } }] } }] });
test('Gemini sends verbatim Japanese and separate style to official host; preserves WAV exactly', async () => {
  let request;
  const result = await synthesizeGemini('生成AIのニュースです。', { key: 'test-only', fetcher: async (url, options) => {
    assert.equal(url, `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`);
    request = options;
    return geminiResponse();
  } });
  assert.deepEqual(result, wav());
  const body = JSON.parse(request.body);
  assert.deepEqual(body.contents[0].parts, [{ text: '生成AIのニュースです。', speech_metadata: { style: GEMINI_STYLE } }]);
  assert.equal(body.generationConfig.speechConfig.voiceConfig.voice, 'Kore');
  assert.equal(request.headers['x-goog-api-key'], 'test-only');
  assert.equal(request.redirect, 'error');
});
test('Gemini rejects errors, interrupted output, raw PCM, truncated WAV and missing audio', async () => {
  for (const response of [new Response('private details', { status: 429 }), geminiResponse(wav(), 'audio/l16'), geminiResponse(wav(), 'audio/wav', 'MAX_TOKENS'), geminiResponse(Buffer.alloc(600)), geminiResponse(wav().subarray(0, 900)), Response.json({ candidates: [] })]) {
    await assert.rejects(synthesizeGemini('ニュース', { key: 'test-only', fetcher: async () => response, sleep: async () => {} }));
  }
  await assert.rejects(synthesizeGemini('ニュース', {}), /not configured/);
});
test('Gemini caches complete voice and changing narration changes cache identity', async () => {
  const data = { date: '2026-10-04', topics: [topic(), { ...topic(), ttsText: '次のニュースです。' }] };
  const saved = new Map(); let calls = 0;
  const publisher = { existing: name => saved.get(name), upload: async name => { const url = `https://example.com/${name}`; saved.set(name, url); return url; } };
  const options = { env: { GEMINI_API_KEY: 'test-only' }, publisher, log: quiet, synth: async () => { calls++; return wav(); } };
  await attachGeminiAudio(data, options); await attachGeminiAudio(data, options);
  assert.equal(calls, 2);
  assert.ok(data.topics.every(t => t.audio[GEMINI_VOICE].endsWith('.wav')));
  assert.notEqual(geminiAssetName(data.topics[0]), geminiAssetName(data.topics[1]));
  assert.notEqual(geminiAssetName(topic()), assetName(topic(), MICROSOFT_VOICES[0]));
});
test('Gemini partial failure never exposes a partial playlist and rerun reuses uploaded articles', async () => {
  const data = { date: '2026-10-04', topics: [topic(), { ...topic(), ttsText: '次' }] };
  const saved = new Map(); let calls = 0;
  const publisher = { existing: name => saved.get(name), upload: async name => { saved.set(name, `https://example.com/${name}`); return saved.get(name); } };
  const options = { env: { GEMINI_API_KEY: 'test-only' }, publisher, log: quiet, synth: async () => { if (++calls === 2) throw new Error('failure'); return wav(); } };
  await attachGeminiAudio(data, options);
  assert.ok(data.topics.every(t => !t.audio?.[GEMINI_VOICE]));
  await attachGeminiAudio(data, options);
  assert.equal(calls, 3); assert.ok(data.topics.every(t => t.audio[GEMINI_VOICE]));
});
test('Gemini missing key or oversized digest makes no API calls', async () => {
  const forbidden = async () => { assert.fail('Unexpected network'); };
  await attachGeminiAudio({ topics: [topic()] }, { env: {}, fetcher: forbidden, log: quiet });
  await attachGeminiAudio({ topics: Array.from({ length: 11 }, topic) }, { env: { GEMINI_API_KEY: 'test-only' }, fetcher: forbidden, log: quiet });
});
test('WAV release uploads declare audio/wav', async () => {
  const publisher = await releasePublisher({ repository: 'owner/repo', token: 'test-only', date: '2026-10-04', fetcher: async (url, request) => {
    if (url.includes('/tags/')) return Response.json({ id: 42 });
    if (url.includes('per_page')) return Response.json([]);
    assert.equal(request.headers['Content-Type'], 'audio/wav');
    return Response.json({ browser_download_url: 'https://github.com/owner/repo/releases/download/day/gemini.wav' });
  } });
  await publisher.upload('gemini.wav', wav());
});

test('Gemini honors Retry-After and succeeds after a transient rate limit', async () => {
  let calls = 0; const waits = [];
  const audio = await synthesizeGemini('ニュース', { key: 'test-only', sleep: async ms => waits.push(ms), fetcher: async () => {
    calls++;
    return calls === 1 ? new Response('', { status: 429, headers: { 'Retry-After': '2' } }) : geminiResponse();
  } });
  assert.deepEqual(audio, wav()); assert.equal(calls, 2); assert.deepEqual(waits, [2000]);
});
test('Gemini exhausted quota has bounded retries and permission failures are not retried', async () => {
  for (const status of [429, 403]) {
    let calls = 0; const waits = [];
    await assert.rejects(synthesizeGemini('ニュース', { key: 'test-only', sleep: async ms => waits.push(ms), fetcher: async () => { calls++; return new Response('', { status }); } }), new RegExp(`HTTP ${status}`));
    assert.equal(calls, status === 429 ? 4 : 1);
    assert.deepEqual(waits, status === 429 ? [60000, 60000, 60000] : []);
  }
});


test('Gemini quota diagnostics classify structured limits without disclosing provider details', async () => {
  let failure; let calls = 0; let waits = 0;
  try {
    await synthesizeGemini('ニュース', { key: 'test-only', sleep: async () => { waits++; }, fetcher: async () => { calls++; return Response.json({ error: {
      message: 'private-project-and-request', details: [{ violations: [{ quotaId: 'GenerateRequestsPerDayPerProjectPerModel', quotaValue: '10' }] }],
    } }, { status: 429 }); } });
  } catch (error) { failure = error; }
  assert.equal(calls, 1); assert.equal(waits, 0);
  assert.equal(failure.quotaPeriod, 'day');
  assert.equal(failure.message, 'Gemini TTS HTTP 429');
  const warnings = [];
  const outcome = await attachGeminiAudio({ topics: [topic()] }, { env: { GEMINI_API_KEY: 'test-only' }, publisher: { existing: () => undefined }, synth: async () => { throw failure; }, log: { info() {}, warn: text => warnings.push(text) } });
  assert.deepEqual(outcome, { status: 'failed', reason: 'daily-quota', generatedCount: 0 });
  assert.match(warnings[0], /日次利用枠/);
  assert.doesNotMatch(warnings.join(''), /private-project|test-only|GenerateRequestsPerDay/);
});
