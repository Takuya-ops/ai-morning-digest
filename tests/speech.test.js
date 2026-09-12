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
