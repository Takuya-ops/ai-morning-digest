import { createHash } from 'node:crypto';
import { speechText } from './speech.js';
export const digestHash = (value) => createHash('sha256').update(value).digest('hex');
export function contentRevision(data) {
  const clean = structuredClone(data);
  delete clean.publication; delete clean.generatedAt; delete clean.audioDurationSec;
  for (const t of clean.topics) { delete t.audio; delete t.audioMetadata; }
  const stable = (v) => Array.isArray(v) ? v.map(stable) : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map(k => [k, stable(v[k])])) : v;
  return digestHash(JSON.stringify(stable(clean)));
}
export function waveInfo(bytes) {
  if (bytes.length < 44 || bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE' || bytes.readUInt32LE(4) + 8 !== bytes.length) throw new Error('Invalid WAV');
  let rate, dataSize;
  for (let offset = 12; offset + 8 <= bytes.length;) {
    const size = bytes.readUInt32LE(offset + 4), id = bytes.toString('ascii', offset, offset + 4), start = offset + 8;
    if (start + size > bytes.length) throw new Error('Truncated WAV chunk');
    if (id === 'fmt ' && size >= 16) {
      if (![1, 3].includes(bytes.readUInt16LE(start))) throw new Error('Unsupported WAV encoding');
      rate = bytes.readUInt32LE(start + 8);
    }
    if (id === 'data') dataSize = size;
    offset = start + size + (size % 2);
  }
  if (!rate || !dataSize) throw new Error('WAV has no audio');
  return { durationSeconds: dataSize / rate, byteLength: bytes.length, mimeType: 'audio/wav', assetSHA256: digestHash(bytes) };
}
export function initializePublication(data, voice, configured) {
  data.schemaVersion = 3;
  for (const t of data.topics) {
    t.articleKey = t.articles[0]?.link;
    const japanese = /[ぁ-んァ-ヶ]/u.test(t.ttsText || `${t.headline} ${t.summary}`);
    const language = japanese ? 'ja' : t.articles[0]?.lang === 'en' ? 'en' : 'und';
    t.editorial = { method: t.aiGenerated ? 'ai_summary' : 'source_excerpt', language, status: language === 'ja' ? 'ready' : language === 'en' ? 'untranslated' : 'unavailable' };
    t.narration = { language, scriptHash: digestHash(speechText(t)) };
  }
  data.publication = { revision: 1, contentRevision: contentRevision(data), textState: 'ready', updatedAt: new Date().toISOString(), audioByVoice: { [voice]: { state: configured ? 'pending' : 'unavailable', expectedCount: data.topics.length, generatedCount: 0 } } };
}
export async function completePublication(data, voice, { fetcher = fetch } = {}) {
  let completed = 0;
  try {
    for (const topic of data.topics) {
      const url = topic.audio?.[voice];
      if (!url) throw new Error('Missing audio');
      const parsed = new URL(url);
      if (parsed.protocol !== 'https:' || parsed.hostname !== 'github.com' || !parsed.pathname.startsWith('/Takuya-ops/ai-morning-digest/releases/download/')) throw new Error('Invalid audio URL');
      const response = await fetcher(url, { signal: AbortSignal.timeout(60000) });
      if (!response.ok || Number(response.headers.get('content-length')) > 32000000) throw new Error('Audio download failed');
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length > 32000000) throw new Error('Audio too large');
      topic.audioMetadata = { ...topic.audioMetadata, [voice]: { ...waveInfo(bytes), scriptHash: topic.narration.scriptHash } };
      completed++;
    }
  } catch {
    for (const topic of data.topics) { if (topic.audio) delete topic.audio[voice]; if (topic.audioMetadata) delete topic.audioMetadata[voice]; }
  }
  const previous = data.publication.audioByVoice[voice];
  const state = completed === data.topics.length && completed > 0 ? 'ready' : previous.state === 'unavailable' ? 'unavailable' : 'failed';
  data.publication.revision++;
  data.publication.updatedAt = new Date().toISOString();
  data.publication.audioByVoice[voice] = { ...previous, generatedCount: completed, state };
  return state;
}
