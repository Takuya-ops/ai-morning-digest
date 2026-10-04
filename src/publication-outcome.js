import { GEMINI_VOICE } from './speech.js';

// Called only after public Pages verification. A known external daily quota
// is degraded service, while configuration, API and publishing errors fail CI.
export function publicationOutcome(data, result) {
  const publication = data?.publication;
  const audio = publication?.audioByVoice?.[GEMINI_VOICE];
  const generation = result?.generation;
  const expected = data?.topics?.length;
  const valid = publication?.textState === 'ready' && expected > 0 && expected <= 10
    && /^[0-9a-f]{64}$/.test(publication.contentRevision ?? '') && Number.isSafeInteger(publication.revision) && publication.revision > 0
    && result?.contentRevision === publication.contentRevision && result?.revision === publication.revision
    && audio?.expectedCount === expected && Number.isInteger(generation?.generatedCount)
    && generation.generatedCount >= 0 && generation.generatedCount <= expected;
  if (!valid) return { level: 'error', message: '配信結果を検証できません。本文・音声の状態と処理ログを確認してください。' };
  if (audio.state === 'ready' && audio.generatedCount === expected && generation.status === 'ready' && generation.generatedCount === expected) {
    return { level: 'success', message: `本文と音声${expected}件の公開を確認しました。` };
  }
  if (audio.state === 'failed' && audio.generatedCount === 0 && generation.status === 'failed' && generation.reason === 'daily-quota') {
    return { level: 'warning', message: `本文の公開は完了しました。Gemini TTSの日次利用枠に達したため音声は未配信です。生成済み${generation.generatedCount}/${expected}件を保持しています。利用枠回復後にretry_audioを実行してください。` };
  }
  return { level: 'error', message: '音声の生成または公開検証に失敗しました。API設定・通信・音声形式を確認してください。' };
}
