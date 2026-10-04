import fs from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
const expected = JSON.parse(fs.readFileSync('docs/data/latest.json'));
const base = process.env.SITE_URL || 'https://takuya-ops.github.io/ai-morning-digest';
for (let attempt = 0; attempt < 20; attempt++) {
  try {
    const response = await fetch(`${base}/data/latest.json?revision=${expected.publication.revision}&check=${Date.now()}`, { signal: AbortSignal.timeout(15000), cache: 'no-store' });
    if (response.ok) {
      const data = await response.json();
      if (data.publication?.contentRevision === expected.publication.contentRevision && data.publication.revision === expected.publication.revision && JSON.stringify(data.publication.audioByVoice) === JSON.stringify(expected.publication.audioByVoice)) {
        console.log('Public Pages JSON matches the generated publication.'); process.exit(0);
      }
    }
  } catch { /* Pages may be rebuilding; retry without logging response bodies. */ }
  if (attempt < 19) await delay(15000);
}
throw new Error('Pages did not publish the expected revision within five minutes');
