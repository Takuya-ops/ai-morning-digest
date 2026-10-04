const key = process.env.GEMINI_API_KEY;
if (!key) throw new Error('GEMINI_API_KEY is missing');
const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key },
  body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: '次のJSONだけを返してください: [{"headline":"日本語の見出し","summary":"音声ニュースの確認です。"}]' }] }], generationConfig: { responseMimeType: 'application/json', maxOutputTokens: 2048 } }), signal: AbortSignal.timeout(60000),
});
const result = await response.json();
console.log(JSON.stringify({ httpStatus: response.status, errorCode: result.error?.status, finishReason: result.candidates?.[0]?.finishReason, textParts: result.candidates?.[0]?.content?.parts?.filter(p => p.text).length }));
if (!response.ok) {
  const list = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000', { headers: { 'x-goog-api-key': key }, signal: AbortSignal.timeout(30000) });
  const models = await list.json();
  console.log(JSON.stringify({ availableTextModels: models.models?.filter(m => m.supportedGenerationMethods?.includes('generateContent') && !/tts|image|audio|vision|robot|computer/i.test(m.name)).map(m => m.name) }));
  throw new Error('Gemini summary API check failed');
}
