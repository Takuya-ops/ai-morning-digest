// Audio is intentionally disabled to avoid recurring TTS API costs.
export const AUDIO_ENABLED = false;
export function disableAudio(data) {
  for (const topic of data.topics || []) {
    delete topic.audio; delete topic.audioMetadata; delete topic.ttsText;
  }
  delete data.audioDurationSec;
  data.features = { ...data.features, audio: false };
  if (data.publication) data.publication.audioByVoice = {};
  return data;
}
