import test from 'node:test';
import assert from 'node:assert/strict';
import { publicationOutcome } from '../src/publication-outcome.js';
import { GEMINI_VOICE } from '../src/speech.js';

function sample(reason = 'daily-quota') {
  return {
    data: { topics: [{}, {}], publication: { textState: 'ready', contentRevision: 'a'.repeat(64), revision: 2, audioByVoice: { [GEMINI_VOICE]: { state: 'failed', expectedCount: 2, generatedCount: 0 } } } },
    result: { contentRevision: 'a'.repeat(64), revision: 2, generation: { status: 'failed', reason, generatedCount: 1 } },
  };
}
test('only an identified daily quota degrades to a warning with audio still unavailable', () => {
  const { data, result } = sample();
  assert.equal(publicationOutcome(data, result).level, 'warning');
  assert.match(publicationOutcome(data, result).message, /1\/2件/);
  assert.equal(data.publication.audioByVoice[GEMINI_VOICE].state, 'failed');
  for (const reason of ['generation-error', 'configuration', 'invalid-input', undefined, 'minute-quota']) {
    result.generation.reason = reason;
    assert.equal(publicationOutcome(data, result).level, 'error');
  }
});
test('stale results, text failure and invalid counts cannot be accepted as quota warnings', () => {
  for (const mutate of [
    ({ result }) => { result.contentRevision = 'old-text'; },
    ({ result }) => { result.revision = 1; },
    ({ data }) => { data.publication.textState = 'failed'; },
    ({ result }) => { result.generation.generatedCount = 3; },
    ({ data }) => { data.publication.audioByVoice[GEMINI_VOICE].generatedCount = 1; },
  ]) {
    const fixture = sample(); mutate(fixture);
    assert.equal(publicationOutcome(fixture.data, fixture.result).level, 'error');
  }
});
test('complete audio needs both generation and public validation to succeed', () => {
  const { data, result } = sample();
  result.generation = { status: 'ready', generatedCount: 2 };
  assert.equal(publicationOutcome(data, result).level, 'error');
  data.publication.audioByVoice[GEMINI_VOICE] = { state: 'ready', expectedCount: 2, generatedCount: 2 };
  assert.equal(publicationOutcome(data, result).level, 'success');
});
