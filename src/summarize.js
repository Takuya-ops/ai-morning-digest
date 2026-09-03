import Anthropic from '@anthropic-ai/sdk';

// ANTHROPIC_API_KEY があれば Claude でトップ記事の日本語見出し・要約を生成する。
// なければ(またはAPIエラー時は)フィードの説明文から要約を組み立てる。

export function fallbackSummary(cluster) {
  // 見出しと要約がズレないよう、代表記事自身の説明文を最優先で使う
  const rep = cluster.representative;
  let source = rep.summary && rep.summary.length > 40 ? rep : null;
  if (!source) {
    const withText = cluster.members.filter((m) => m.summary && m.summary.length > 40);
    withText.sort((a, b) => (b.lang === 'ja') - (a.lang === 'ja') || b.summary.length - a.summary.length);
    source = withText[0] || rep;
  }
  const text = (source.summary || '').slice(0, 400);
  const cut = text.length >= 400 ? `${text.replace(/[^。.!?！？]*$/, '')}…` : text;
  return {
    headline: cluster.representative.title,
    summary: cut || '(要約情報なし。リンク先をご確認ください)',
    whyItMatters: '',
  };
}

function buildPrompt(clusters) {
  const topics = clusters.map((c, i) => ({
    index: i,
    titles: c.members.slice(0, 6).map((m) => `[${m.feedName}] ${m.title}`),
    excerpts: c.members
      .filter((m) => m.summary)
      .slice(0, 4)
      .map((m) => m.summary.slice(0, 500)),
  }));
  return (
    '以下は今朝の生成AI関連ニュースのトピック一覧です。各トピックは複数媒体の記事をまとめたものです。\n' +
    '各トピックについて、次のJSON配列だけを出力してください(前後に説明文を付けない):\n' +
    '[{"index": 0, "headline": "日本語の見出し(40字以内)", "summary": "記事内容の日本語要約。2〜4文、150〜250字程度。事実ベースで具体的に(何が・誰が・どうなった)。", "whyItMatters": "なぜ重要かを1文で"}, ...]\n' +
    '英語トピックも日本語に訳してください。記事に書かれていないことは推測で書かないでください。\n\n' +
    JSON.stringify(topics, null, 1)
  );
}

function extractJson(text) {
  const start = text.indexOf('[');
  const end = text.lastIndexOf(']');
  if (start === -1 || end <= start) throw new Error('no JSON array in response');
  return JSON.parse(text.slice(start, end + 1));
}

export async function summarizeTopics(clusters) {
  if (!process.env.ANTHROPIC_API_KEY) {
    console.log('summarize: ANTHROPIC_API_KEY 未設定のためフィード説明文から要約を生成します');
    return clusters.map((c) => fallbackSummary(c));
  }
  const client = new Anthropic();
  const model = process.env.SUMMARY_MODEL || 'claude-opus-5';
  const params = {
    model,
    max_tokens: 16000,
    system: 'あなたは日本語のテクノロジーニュース編集者です。正確で簡潔な要約を書きます。',
    messages: [{ role: 'user', content: buildPrompt(clusters) }],
  };
  try {
    let response;
    try {
      // claude-opus-5 では安全分類器による拒否時のサーバーサイドフォールバックを既定で有効化
      response = await client.beta.messages.create({
        ...params,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
      });
    } catch (err) {
      if (err instanceof Anthropic.BadRequestError) {
        response = await client.messages.create(params);
      } else {
        throw err;
      }
    }
    if (response.stop_reason === 'refusal') throw new Error('summarization refused');
    const text = response.content
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('');
    const parsed = extractJson(text);
    return clusters.map((c, i) => {
      const hit = parsed.find((p) => p.index === i);
      if (hit && hit.headline && hit.summary) {
        return {
          headline: String(hit.headline),
          summary: String(hit.summary),
          whyItMatters: String(hit.whyItMatters || ''),
        };
      }
      return fallbackSummary(c);
    });
  } catch (err) {
    console.warn(`summarize: Claude要約に失敗したためフォールバックします: ${err.message}`);
    return clusters.map((c) => fallbackSummary(c));
  }
}
