// 生成AI関連判定とエンティティ抽出のためのパターン定義

// aiOnly=false のフィードから生成AI関連記事を拾うためのパターン
export const AI_PATTERNS = [
  /生成\s?AI/, /生成系AI/, /人工知能/, /大規模言語モデル/, /基盤モデル/, /画像生成/, /動画生成/, /音声生成/,
  /AIエージェント/, /AIモデル/, /AIチャット/, /AIアシスタント/, /機械学習/, /深層学習/, /チャットボット/,
  /\bAI\b/, /\bA\.I\.\b/, /\bLLMs?\b/, /\bgenerative\b/i, /\bGenAI\b/i, /\bAGI\b/,
  /\bChatGPT\b/i, /\bGPT-?\d/i, /\bOpenAI\b/i, /オープンAI/,
  /\bClaude\b/i, /\bAnthropic\b/i, /\bGemini\b/i, /\bDeepMind\b/i, /\bCopilot\b/i, /\bNotebookLM\b/i,
  /\bLlama\b/i, /\bMistral\b/i, /\bDeepSeek\b/i, /\bQwen\b/i, /\bGrok\b/, /\bxAI\b/,
  /\bStable Diffusion\b/i, /\bMidjourney\b/i, /\bSora\b/, /\bDALL[·-]?E\b/i, /\bVeo\b/,
  /\bHugging ?Face\b/i, /\bPerplexity\b/i, /\bfine-?tun/i, /ファインチューニング/, /プロンプト/,
  /\bfoundation model/i, /\bfrontier model/i, /\bdiffusion model/i, /\btransformer\b/i,
  /\bneural net/i, /\bmachine learning\b/i, /\bdeep learning\b/i, /\bagentic\b/i, /\bchatbot\b/i,
  /\bMCP\b/, /\bRAG\b/, /\bvibe coding\b/i, /バイブコーディング/, /\binference chip/i, /\bGPU\b.*(AI|モデル|学習)/i,
];

export function isAiRelated(text) {
  return AI_PATTERNS.some((re) => re.test(text));
}

// トピッククラスタリング用のエンティティ辞書(言語をまたいで同一トピックを束ねる鍵)
export const ENTITIES = [
  ['openai', /\bopenai\b|オープンai/i],
  ['chatgpt', /\bchatgpt\b|チャットgpt/i],
  ['gpt', /\bgpt[-\s]?[0-9o]/i],
  ['anthropic', /\banthropic\b|アンソロピック/i],
  ['claude', /\bclaude\b|クロード/i],
  ['google', /\bgoogle\b|グーグル/i],
  ['gemini', /\bgemini\b|ジェミニ/i],
  ['deepmind', /\bdeepmind\b|ディープマインド/i],
  ['microsoft', /\bmicrosoft\b|マイクロソフト/i],
  ['copilot', /\bcopilot\b|コパイロット/i],
  ['meta', /\bmeta\b|メタ社/i],
  ['llama', /\bllama\b/i],
  ['nvidia', /\bnvidia\b|エヌビディア/i],
  ['apple', /\bapple\b|アップル/i],
  ['amazon', /\bamazon\b|アマゾン/i],
  ['aws', /\baws\b/i],
  ['mistral', /\bmistral\b|ミストラル/i],
  ['deepseek', /\bdeepseek\b|ディープシーク/i],
  ['xai', /\bxai\b/i],
  ['grok', /\bgrok\b/i],
  ['sora', /\bsora\b/i],
  ['veo', /\bveo\b/i],
  ['midjourney', /\bmidjourney\b/i],
  ['stability', /\bstability ?ai\b|stable diffusion/i],
  ['huggingface', /\bhugging ?face\b/i],
  ['perplexity', /\bperplexity\b|パープレキシティ/i],
  ['cursor', /\bcursor\b/i],
  ['github', /\bgithub\b/i],
  ['notebooklm', /\bnotebooklm\b/i],
  ['qwen', /\bqwen\b/i],
  ['alibaba', /\balibaba\b|アリババ/i],
  ['softbank', /\bsoftbank\b|ソフトバンク/i],
  ['sakana', /\bsakana\b|サカナ/i],
  ['rakuten', /\brakuten\b|楽天/i],
  ['ntt', /\bntt\b/i],
  ['fujitsu', /\bfujitsu\b|富士通/i],
  ['nec', /\bNEC\b/],
  ['sony', /\bsony\b|ソニー/i],
  ['samsung', /\bsamsung\b|サムスン/i],
  ['intel', /\bintel\b|インテル/i],
  ['amd', /\bAMD\b/],
  ['tsmc', /\btsmc\b/i],
  ['oracle', /\boracle\b|オラクル/i],
  ['salesforce', /\bsalesforce\b|セールスフォース/i],
  ['adobe', /\badobe\b|アドビ/i],
  ['tesla', /\btesla\b|テスラ/i],
  ['line-yahoo', /lineヤフー|line yahoo/i],
];

export function extractEntities(text) {
  const found = new Set();
  for (const [name, re] of ENTITIES) {
    if (re.test(text)) found.add(name);
  }
  return found;
}
