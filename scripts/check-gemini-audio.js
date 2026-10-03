import { mkdir, writeFile } from 'node:fs/promises';
import { synthesizeGemini, GEMINI_MODEL, GEMINI_VOICE } from '../src/speech.js';

const text = 'おはようございます。生成AIモーニングダイジェストです。今日のニュースを、わかりやすくお伝えします。GoogleのGemini、OpenAIのChatGPT、そしてClaudeの最新情報を確認しましょう。';
try {
  const bytes = await synthesizeGemini(text, { key: process.env.GEMINI_API_KEY });
  await mkdir('audio-check', { recursive: true });
  await writeFile('audio-check/gemini-sample.wav', bytes);
  await writeFile('audio-check/sample.json', JSON.stringify({ model: GEMINI_MODEL, voice: GEMINI_VOICE, text, bytes: bytes.length }, null, 2));
  console.log(`Gemini TTS: WAV ${bytes.length} bytes generated successfully.`);
} catch (error) {
  console.error(/^Gemini TTS HTTP \d{3}$/.test(error.message) ? error.message : 'Gemini TTS sample failed. Check GEMINI_API_KEY and API quota.');
  process.exitCode = 1;
}
