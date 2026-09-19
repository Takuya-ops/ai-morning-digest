import { createHash } from 'node:crypto';

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

// MP3s are release assets, not daily binary commits in git history.
export async function releasePublisher({ repository, token, date, commit, fetcher = fetch }) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository || '') || !token || !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error('GitHub audio publishing configuration missing');
  const base = `https://api.github.com/repos/${repository}`;
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'AI-Morning-Digest' };
  const tag = `digest-audio-${date}`;
  let response = await fetcher(`${base}/releases/tags/${tag}`, { headers, redirect: 'error', signal: AbortSignal.timeout(30_000) });
  if (response.status === 404) {
    response = await fetcher(`${base}/releases`, {
      method: 'POST', headers: { ...headers, 'Content-Type': 'application/json' }, redirect: 'error', signal: AbortSignal.timeout(30_000),
      body: JSON.stringify({ tag_name: tag, target_commitish: commit || 'main', name: `Daily briefing audio ${date}`, body: 'Pre-generated Microsoft Nanami / Keita narration of the daily digest. Source attribution is in the matching digest JSON.', make_latest: 'false' }),
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
        method: 'POST', headers: { ...headers, 'Content-Type': 'audio/mpeg' }, body: bytes, redirect: 'error', signal: AbortSignal.timeout(60_000),
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
