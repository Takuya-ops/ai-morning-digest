import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';

// Official Azure Speech REST API. No browser/Edge impersonation or shared app key.
export const MICROSOFT_VOICES = ['ja-JP-NanamiNeural', 'ja-JP-KeitaNeural'];
const escapeXML = (text) => String(text).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c]);
export function speechText(topic) {
  return String(topic.ttsText || `${topic.headline}。${topic.summary || ''}`)
    .replace(/https?:\/\/\S+/g, '').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '').trim().slice(0, 2500);
}
export function assetName(topic, voice) {
  const hash = createHash('sha256').update(`${voice}\n${speechText(topic)}`).digest('hex').slice(0, 24);
  return `${hash}-${voice}.mp3`;
}
export async function synthesize(text, voice, { key, region, fetcher = fetch }) {
  if (!MICROSOFT_VOICES.includes(voice)) throw new Error('Unsupported Microsoft voice');
  if (!key || !/^[a-z][a-z0-9]{2,40}$/.test(region || '')) throw new Error('Azure Speech key/region not configured');
  const response = await fetcher(`https://${region}.tts.speech.microsoft.com/cognitiveservices/v1`, {
    method: 'POST', redirect: 'error', signal: AbortSignal.timeout(60_000),
    headers: {
      'Ocp-Apim-Subscription-Key': key,
      'Content-Type': 'application/ssml+xml',
      'X-Microsoft-OutputFormat': 'audio-24khz-48kbitrate-mono-mp3',
      'User-Agent': 'AI-Morning-Digest',
    },
    body: `<speak version="1.0" xml:lang="ja-JP"><voice name="${voice}">${escapeXML(text)}</voice></speak>`,
  });
  if (!response.ok) throw new Error(`Azure Speech HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 500 || bytes.length > 8_000_000) throw new Error('Invalid Azure audio size');
  return bytes;
}

// Audio files are release assets, not daily binary commits in git history.
export async function releasePublisher({ repository, token, date, commit, fetcher = fetch }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository || '') || !token || !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('GitHub audio publishing configuration missing');
  const base = `https://api.github.com/repos/${repository}`;
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'AI-Morning-Digest' };
  const tag = `digest-audio-${date}`;
  let response = await fetcher(`${base}/releases/tags/${tag}`, { headers, redirect: 'error', signal: AbortSignal.timeout(30_000) });
  if (response.status === 404) {
    response = await fetcher(`${base}/releases`, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, redirect: 'error', signal: AbortSignal.timeout(30_000),
      body: JSON.stringify({ tag_name: tag, target_commitish: commit || 'main', name: `Daily briefing audio ${date}`, body: 'Pre-generated narration of the daily digest. Source attribution is in the matching digest JSON.', make_latest: 'false' }),
    });
  }
  if (!response.ok) throw new Error(`GitHub audio release HTTP ${response.status}`);
  const release = await response.json();
  if (!Number.isSafeInteger(release.id)) throw new Error('Invalid release ID');
  const assets = new Map();
  // A daily release has at most 20 assets; pagination also covers reruns with changed text.
  for (let page = 1; page <= 10; page++) {
    const listed = await fetcher(`${base}/releases/${release.id}/assets?per_page=100&page=${page}`, { headers, redirect: 'error', signal: AbortSignal.timeout(30_000) });
    if (!listed.ok) throw new Error(`GitHub audio assets HTTP ${listed.status}`);
    const rows = await listed.json();
    if (!Array.isArray(rows)) throw new Error('Invalid audio asset list');
    for (const asset of rows) {
      const url = checkedDownloadURL(asset.browser_download_url, repository);
      if (asset.state === 'uploaded' && asset.size >= 500 && url) assets.set(asset.name, url);
    }
    if (rows.length < 100) break;
  }
  return {
    existing: (name) => assets.get(name),
    upload: async (name, bytes) => {
      // Construct the host ourselves: never send the token to an API-provided URL.
      const uploaded = await fetcher(`https://uploads.github.com/repos/${repository}/releases/${release.id}/assets?name=${encodeURIComponent(name)}`, {
        method: 'POST', headers: { ...headers, 'Content-Type': name.endsWith('.wav') ? 'audio/wav' : 'audio/mpeg' }, body: bytes, redirect: 'error', signal: AbortSignal.timeout(60_000),
      });
      if (!uploaded.ok) throw new Error(`GitHub audio upload HTTP ${uploaded.status}`);
      const asset = await uploaded.json();
      const url = checkedDownloadURL(asset.browser_download_url, repository);
      if (!url) throw new Error('Invalid audio download URL');
      assets.set(name, url); return url;
    },
  };
}
function checkedDownloadURL(value, repository) {
  try { const url = new URL(value); return url.protocol === 'https:' && url.host === 'github.com' && url.pathname.startsWith(`/${repository}/releases/download/`) ? url.href : null; }
  catch { return null; }
}

export async function attachMicrosoftAudio(data, {
  env = process.env, fetcher = fetch, publisher, synth = synthesize, log = console,
} = {}) {
  if (!env.AZURE_SPEECH_KEY || !env.AZURE_SPEECH_REGION) {
    log.info('speech: Azure Speech未設定。Microsoft音声の生成をスキップします。'); return;
  }
  if (!data.topics.length || data.topics.length > 10) {
    log.warn('speech: 音声生成は1日最大10記事です。DIGEST_TOP_Nを1〜10に設定してください。'); return;
  }
  try {
    publisher ||= await releasePublisher({ repository: env.GITHUB_REPOSITORY, token: env.GITHUB_TOKEN, date: data.date, commit: env.GITHUB_SHA, fetcher });
    for (const voice of MICROSOFT_VOICES) {
      const completed = [];
      try {
        for (const topic of data.topics) {
          const name = assetName(topic, voice);
          // Reuse the same text/voice on reruns, so Azure is not charged twice.
          const url = publisher.existing(name) || await publisher.upload(name, await synth(speechText(topic), voice, { key: env.AZURE_SPEECH_KEY, region: env.AZURE_SPEECH_REGION, fetcher }));
          completed.push([topic, url]);
        }
        // Expose a voice only when every article can play in sequence.
        for (const [topic, url] of completed) topic.audio = { ...topic.audio, [voice]: url };
        log.info(`speech: ${voice} ${completed.length}記事を配信に追加しました。`);
      } catch { log.warn(`speech: ${voice}の生成または配信に失敗。ニュースの生成は継続します。Azureのリージョン・残高とGitHubの権限を確認してください。`); }
    }
  } catch { log.warn('speech: 音声配信の準備に失敗。GitHubのリポジトリ名・contents:write権限を確認してください。ニュースの生成は継続します。'); }
}


export const GEMINI_MODEL = 'gemini-3.8-flash-tts';
export const GEMINI_VOICE = 'gemini-3.8-flash-tts-Kore';
export const GEMINI_STYLE = '標準的な日本語のニュースナレーション。落ち着いた自然な声で、明瞭に、少しゆっくり読み上げてください。文の区切りで短く間を取り、数字と英語の製品名を丁寧に発音してください。ささやき声や大げさな演技は避けてください。';
export function geminiAssetName(topic) {
  const hash = createHash('sha256').update(`${GEMINI_MODEL}\nKore\n${GEMINI_STYLE}\nwav-v1\n${speechText(topic)}`).digest('hex').slice(0, 24);
  return `${hash}-${GEMINI_VOICE}.wav`;
}
export async function synthesizeGemini(text, { key, fetcher = fetch, sleep = delay } = {}) {
  if (!key) throw new Error('GEMINI_API_KEY not configured');
  if (!text?.trim()) throw new Error('Empty narration');
  const request = {
    method: 'POST', redirect: 'error',
    headers: { 'x-goog-api-key': key, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text, speech_metadata: { style: GEMINI_STYLE } }] }],
      generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { voice: 'Kore' } } },
    }),
  };
  let response;
  for (let attempt = 0; attempt < 4; attempt++) {
    response = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`, { ...request, signal: AbortSignal.timeout(120_000) });
    if (![429, 503].includes(response.status) || attempt === 3) break;
    const retryAfter = response.headers.get('retry-after');
    const seconds = retryAfter && /^\d+$/.test(retryAfter) ? Number(retryAfter) : retryAfter ? (Date.parse(retryAfter) - Date.now()) / 1000 : NaN;
    // Free-tier minute limits can be lower than a ten-article digest. Bound
    // retries also for daily quota exhaustion; never expose API error bodies.
    await response.body?.cancel();
    await sleep(Number.isFinite(seconds) ? Math.min(120, Math.max(1, seconds)) * 1000 : 60_000);
  }
  // Never log provider response bodies, which can contain request details.
  if (!response.ok) {
    const error = new Error(`Gemini TTS HTTP ${response.status}`);
    // Classify structured quota fields only. Never log the provider's message,
    // project identifiers, request text, API key, or complete response body.
    if (response.status === 429) {
      const body = await response.json().catch(() => ({}));
      const details = Array.isArray(body.error?.details) ? body.error.details : [];
      const fields = details.flatMap(detail => Array.isArray(detail.violations) ? detail.violations : [])
        .flatMap(v => [v.quotaId, v.quotaMetric]).filter(v => typeof v === 'string').join(' ');
      error.quotaPeriod = /per[_-]?day/i.test(fields) ? 'day' : /per[_-]?minute/i.test(fields) ? 'minute' : 'unknown';
    }
    throw error;
  }
  const result = await response.json();
  const candidate = result.candidates?.[0];
  if (candidate?.finishReason !== 'STOP') throw new Error('Incomplete Gemini narration');
  const parts = candidate.content?.parts?.filter(part => part.inlineData) || [];
  if (parts.length !== 1) throw new Error('Missing or ambiguous Gemini audio');
  const { data, mimeType } = parts[0].inlineData;
  if (!['audio/wav', 'audio/x-wav'].includes(mimeType) || typeof data !== 'string' || data.length > 43_000_000) throw new Error('Invalid Gemini audio format');
  const bytes = Buffer.from(data, 'base64');
  // 3.8 returns a complete WAV, unlike older models' headerless PCM.
  if (bytes.length < 500 || bytes.length > 32_000_000 || bytes.toString('ascii', 0, 4) !== 'RIFF' || bytes.toString('ascii', 8, 12) !== 'WAVE' || bytes.readUInt32LE(4) + 8 !== bytes.length) throw new Error('Invalid Gemini WAV');
  return bytes;
}

export async function attachGeminiAudio(data, {
  env = process.env, fetcher = fetch, publisher, synth = synthesizeGemini, log = console,
} = {}) {
  if (!env.GEMINI_API_KEY) {
    log.warn('speech: GEMINI_API_KEY未設定。Gemini音声は未配信です。'); return;
  }
  if (!data.topics.length || data.topics.length > 10) {
    log.warn('speech: 音声生成は1日最大10記事です。'); return;
  }
  // A rerun must not advertise stale or only partially completed narration.
  for (const topic of data.topics) { if (topic.audio) delete topic.audio[GEMINI_VOICE]; }
  try {
    publisher ||= await releasePublisher({ repository: env.GITHUB_REPOSITORY, token: env.GITHUB_TOKEN, date: data.date, commit: env.GITHUB_SHA, fetcher });
    const completed = [];
    for (const topic of data.topics) {
      const name = geminiAssetName(topic);
      const url = publisher.existing(name) || await publisher.upload(name, await synth(speechText(topic), { key: env.GEMINI_API_KEY, fetcher }));
      completed.push([topic, url]);
    }
    for (const [topic, url] of completed) topic.audio = { ...topic.audio, [GEMINI_VOICE]: url };
    log.info(`speech: Gemini 3.8 Flash TTS ${completed.length}記事を配信に追加しました。`);
  } catch (error) {
    const period = { day: '・日次利用枠', minute: '・分単位の利用枠', unknown: '・利用枠の種類は未特定' }[error.quotaPeriod] || '';
    const status = /^Gemini TTS HTTP \d{3}$/.test(error.message) ? ` (${error.message}${period})` : '';
    log.warn(`speech: Gemini音声の生成・配信に失敗${status}。APIキー・利用枠・GitHub権限を確認してください。ニュースの生成は継続します。`);
  }
}
