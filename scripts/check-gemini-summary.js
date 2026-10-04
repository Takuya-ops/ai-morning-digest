import { geminiSummaryResponse } from '../src/summarize.js';
if (!process.env.GEMINI_API_KEY) throw new Error('GEMINI_API_KEY is missing');
const result = await geminiSummaryResponse('次のJSONだけを返してください: [{"headline":"日本語の見出し","summary":"音声ニュースの確認です。"}]', { key: process.env.GEMINI_API_KEY });
console.log(JSON.stringify({ model: result.model, entries: result.parsed.length, japanese: /[ぁ-んァ-ヶ]/u.test(JSON.stringify(result.parsed)) }));
