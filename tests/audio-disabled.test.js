import test from 'node:test';
import assert from 'node:assert/strict';
import { AUDIO_ENABLED, disableAudio } from '../src/audio-policy.js';
import { attachGeminiAudio, attachMicrosoftAudio } from '../src/speech.js';
test('production audio remains disabled even when both providers have keys', async () => {
  assert.equal(AUDIO_ENABLED, false);
  const forbidden = async () => { assert.fail('Audio API must not be called'); };
  const options = { env: { GEMINI_API_KEY: 'test', AZURE_SPEECH_KEY: 'test', AZURE_SPEECH_REGION: 'japaneast' }, fetcher: forbidden, synth: forbidden };
  for (const attach of [attachGeminiAudio, attachMicrosoftAudio]) assert.equal((await attach({ topics: [{}] }, options)).status, 'disabled');
});
test('disabling old published audio preserves readable articles', () => {
  const data = { topics: [{ headline: '残す本文', summary: '本文', ttsText: '台本', audio: { old: 'https://example.com/a.wav' }, audioMetadata: {} }], audioDurationSec: 10, publication: { textState: 'ready', audioByVoice: { old: { state: 'ready' } } } };
  disableAudio(data); disableAudio(data);
  assert.equal(data.topics[0].headline, '残す本文'); assert.equal(data.topics[0].audio, undefined); assert.equal(data.topics[0].ttsText, undefined);
  assert.equal(data.features.audio, false); assert.deepEqual(data.publication.audioByVoice, {}); assert.equal(data.publication.textState, 'ready');
});
