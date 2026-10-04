// Native media controls; external audio is intentionally outside the service-worker cache.
(() => {
  const root = document.getElementById('briefing-player');
  if (!root) return;
  const data = JSON.parse(document.getElementById('briefing-audio-data').textContent);
  const audio = root.querySelector('audio'), voice = root.querySelector('[data-voice]'), title = root.querySelector('[data-title]'), status = root.querySelector('[role="status"]'), next = root.querySelector('[data-next]');
  const labels = { 'gemini-3.8-flash-tts-Kore': 'Gemini 3.8（Kore）', 'ja-JP-NanamiNeural': 'Nanami', 'ja-JP-KeitaNeural': 'Keita' };
  let queue = [], index = 0;
  const voices = [...new Set(data.flatMap(item => Object.keys(item.audio || {})))];
  voices.forEach(id => { const option = document.createElement('option'); option.value = id; option.textContent = labels[id] || id; voice.append(option); });
  const load = () => {
    audio.pause(); audio.removeAttribute('src');
    if (!queue.length) { title.textContent = '音声は準備中、または未配信です。本文は読めます。'; next.disabled = true; audio.load(); return; }
    const item = queue[index]; audio.src = item.audio[voice.value]; audio.load();
    title.textContent = `${index + 1}/${queue.length} · ${item.headline}`; next.disabled = index + 1 >= queue.length; status.textContent = '';
  };
  const play = () => audio.play().catch(() => { status.textContent = '再生を開始できませんでした。再生ボタンを押してください。'; });
  const advance = () => { if (index + 1 < queue.length) { index++; load(); play(); } };
  voice.addEventListener('change', () => { index = 0; queue = data.filter(item => item.audio?.[voice.value]); load(); });
  next.addEventListener('click', advance); audio.addEventListener('ended', advance);
  audio.addEventListener('error', () => { if (audio.getAttribute('src')) status.textContent = '音声を取得できませんでした。接続を確認して再試行してください。'; });
  root.querySelector('[data-rate]').addEventListener('change', event => { audio.playbackRate = Number(event.target.value); });
  audio.addEventListener('loadedmetadata', () => { audio.playbackRate = Number(root.querySelector('[data-rate]').value); });
  queue = data.filter(item => item.audio?.[voice.value]); load();
})();
