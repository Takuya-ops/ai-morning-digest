// 収集対象フィード一覧(2026-09-03 全URL疎通検証済み)
// weight: トピックの「大きさ」算出に使うソース影響度 (1-5)
// aiOnly: true なら全記事をAI関連として扱う / false ならキーワードフィルタを適用
export const FEEDS = [
  // --- 日本語メディア ---
  { id: 'itmedia-aiplus', name: 'ITmedia AI+', url: 'https://rss.itmedia.co.jp/rss/2.0/aiplus.xml', weight: 4, lang: 'ja', aiOnly: true },
  { id: 'itmedia-news', name: 'ITmedia NEWS', url: 'https://rss.itmedia.co.jp/rss/2.0/news_bursts.xml', weight: 3, lang: 'ja', aiOnly: false },
  { id: 'nikkei-xtech', name: '日経クロステック', url: 'https://xtech.nikkei.com/rss/index.rdf', weight: 3, lang: 'ja', aiOnly: false },
  { id: 'publickey', name: 'Publickey', url: 'https://www.publickey1.jp/atom.xml', weight: 3, lang: 'ja', aiOnly: false },
  { id: 'gigazine', name: 'GIGAZINE', url: 'https://gigazine.net/news/rss_2.0/', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'cnet-japan', name: 'CNET Japan', url: 'https://feeds.japan.cnet.com/rss/cnet/all.rdf', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'zdnet-japan', name: 'ZDNET Japan', url: 'https://feeds.japan.zdnet.com/rss/zdnet/all.rdf', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'ascii', name: 'ASCII.jp', url: 'https://ascii.jp/rss.xml', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'impress-watch', name: 'Impress Watch', url: 'https://www.watch.impress.co.jp/data/rss/1.0/ipw/feed.rdf', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'internet-watch', name: 'INTERNET Watch', url: 'https://internet.watch.impress.co.jp/data/rss/1.0/iw/feed.rdf', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'pc-watch', name: 'PC Watch', url: 'https://pc.watch.impress.co.jp/data/rss/1.0/pcw/feed.rdf', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'gihyo', name: 'gihyo.jp', url: 'https://gihyo.jp/feed/rss2', weight: 2, lang: 'ja', aiOnly: false },
  { id: 'codezine', name: 'CodeZine', url: 'https://codezine.jp/rss/new/20/index.xml', weight: 2, lang: 'ja', aiOnly: false },

  // --- 海外ベンダー公式 ---
  { id: 'openai', name: 'OpenAI', url: 'https://openai.com/news/rss.xml', weight: 5, lang: 'en', aiOnly: true },
  { id: 'google-ai', name: 'Google AI Blog', url: 'https://blog.google/technology/ai/rss/', weight: 4, lang: 'en', aiOnly: true },
  { id: 'deepmind', name: 'Google DeepMind', url: 'https://deepmind.google/blog/rss.xml', weight: 4, lang: 'en', aiOnly: true },
  { id: 'microsoft', name: 'Microsoft Blog', url: 'https://blogs.microsoft.com/feed/', weight: 3, lang: 'en', aiOnly: false },
  { id: 'nvidia', name: 'NVIDIA Blog', url: 'https://blogs.nvidia.com/feed/', weight: 3, lang: 'en', aiOnly: false },
  { id: 'huggingface', name: 'Hugging Face', url: 'https://huggingface.co/blog/feed.xml', weight: 3, lang: 'en', aiOnly: true },
  { id: 'mistral', name: 'Mistral AI', url: 'https://mistral.ai/rss.xml', weight: 3, lang: 'en', aiOnly: true },
  { id: 'stability', name: 'Stability AI', url: 'https://stability.ai/news-updates?format=rss', weight: 2, lang: 'en', aiOnly: true },
  { id: 'aws-ml', name: 'AWS AI Blog', url: 'https://aws.amazon.com/blogs/machine-learning/feed/', weight: 2, lang: 'en', aiOnly: true },

  // --- 海外メディア ---
  { id: 'techcrunch-ai', name: 'TechCrunch AI', url: 'https://techcrunch.com/category/artificial-intelligence/feed/', weight: 4, lang: 'en', aiOnly: true },
  { id: 'verge-ai', name: 'The Verge AI', url: 'https://www.theverge.com/rss/ai-artificial-intelligence/index.xml', weight: 3, lang: 'en', aiOnly: true },
  { id: 'mit-tr-ai', name: 'MIT Tech Review', url: 'https://www.technologyreview.com/topic/artificial-intelligence/feed/', weight: 3, lang: 'en', aiOnly: true },
  { id: 'ars-ai', name: 'Ars Technica AI', url: 'https://arstechnica.com/ai/feed/', weight: 3, lang: 'en', aiOnly: true },
  { id: 'venturebeat-ai', name: 'VentureBeat AI', url: 'https://venturebeat.com/category/ai/feed', weight: 2, lang: 'en', aiOnly: true },
  { id: 'the-decoder', name: 'The Decoder', url: 'https://the-decoder.com/feed/', weight: 2, lang: 'en', aiOnly: true },
  { id: 'hn-front', name: 'Hacker News', url: 'https://hnrss.org/frontpage', weight: 3, lang: 'en', aiOnly: false },
  { id: 'simonwillison', name: 'Simon Willison', url: 'https://simonwillison.net/atom/everything/', weight: 2, lang: 'en', aiOnly: false },

  // --- コミュニティ(参考・低ウェイト) ---
  { id: 'zenn-genai', name: 'Zenn 生成AI', url: 'https://zenn.dev/topics/%E7%94%9F%E6%88%90ai/feed', weight: 1, lang: 'ja', aiOnly: true },
  { id: 'qiita-genai', name: 'Qiita 生成AI', url: 'https://qiita.com/tags/%E7%94%9F%E6%88%90ai/feed', weight: 1, lang: 'ja', aiOnly: true },
];
