import fs from 'node:fs';
import { publicationOutcome } from '../src/publication-outcome.js';

const data = JSON.parse(fs.readFileSync('docs/data/latest.json'));
const result = JSON.parse(fs.readFileSync('.work/audio-result.json'));
const outcome = publicationOutcome(data, result);
const heading = { success: '本文・音声の配信完了', warning: '本文配信完了・音声は利用枠待ち', error: '配信エラー' }[outcome.level];
if (process.env.GITHUB_STEP_SUMMARY) {
  fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, `## ${heading}\n\n${outcome.message}\n`);
}
if (outcome.level === 'success') console.log(outcome.message);
else console.log(`::${outcome.level} title=${heading}::${outcome.message}`);
if (outcome.level === 'error') process.exitCode = 1;
