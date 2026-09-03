// SLACK_WEBHOOK_URL が設定されていれば、生成したダイジェストの概要をSlackに通知する(任意機能)

// Slack mrkdwnでは & < > のエスケープが必須。リンクURL側は | や空白がリンク構文を壊すためエンコードする
const escMrkdwn = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const escLinkUrl = (u) => String(u).replace(/[|<>\s]/g, (ch) => encodeURIComponent(ch));

export async function notifySlack(data, siteUrl) {
  const webhook = process.env.SLACK_WEBHOOK_URL;
  if (!webhook) return;

  const lines = data.topics
    .slice(0, 10)
    .map((t) => `${t.rank}. <${escLinkUrl(t.articles[0].link)}|${escMrkdwn(t.headline)}>`)
    .join('\n');
  const payload = {
    text: `🌅 生成AIモーニングダイジェスト ${data.date}`,
    blocks: [
      {
        type: 'header',
        text: { type: 'plain_text', text: `🌅 生成AIモーニングダイジェスト ${data.date}`, emoji: true },
      },
      { type: 'section', text: { type: 'mrkdwn', text: lines || '本日のトピックはありません' } },
      {
        type: 'section',
        text: { type: 'mrkdwn', text: `<${siteUrl}|📖 全${data.stats.articleCount}件をWebで見る>` },
      },
    ],
  };
  const res = await fetch(webhook, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    console.warn(`notify: Slack通知に失敗しました (HTTP ${res.status})`);
  } else {
    console.log('notify: Slackに通知しました');
  }
}
