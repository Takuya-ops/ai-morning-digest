// Republish existing news without making summarization or TTS API calls.
import fs from 'node:fs';
import { disableAudio } from '../src/audio-policy.js';
import { contentRevision } from '../src/publication.js';
import { renderSite } from '../src/render.js';
const dir = 'docs/data';
for (const name of fs.readdirSync(dir).filter(name => /^(latest|\d{4}-\d{2}-\d{2})\.json$/.test(name))) {
  const file = `${dir}/${name}`, data = JSON.parse(fs.readFileSync(file));
  const before = JSON.stringify(data);
  disableAudio(data);
  if (before !== JSON.stringify(data) && data.publication) {
    data.publication.revision++;
    data.publication.contentRevision = contentRevision(data);
    data.publication.updatedAt = new Date().toISOString();
  }
  fs.writeFileSync(file, JSON.stringify(data, null, 1));
}
renderSite(JSON.parse(fs.readFileSync(`${dir}/latest.json`)), 'docs');
console.log('Existing news republished with audio disabled. No generation APIs called.');
