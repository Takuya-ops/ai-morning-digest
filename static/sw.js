// ネットワーク優先 + キャッシュフォールバック:
// オンラインなら常に最新のダイジェストを表示し、オフラインでも直近の表示内容を開けるようにする
// キャッシュ名は必ず PREFIX で始める: username.github.io はプロジェクト間でオリジンを共有するため、
// 自分のキャッシュだけを掃除しないと他プロジェクトのオフラインデータを消してしまう
const PREFIX = 'ai-digest-';
const CACHE = `${PREFIX}v1`;

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((k) => k.startsWith(PREFIX) && k !== CACHE).map((k) => caches.delete(k))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  event.respondWith(
    fetch(req)
      .then((res) => {
        if (res.ok) {
          const copy = res.clone();
          // waitUntilで書き込み完了までSWを生かす(respondWith直後の終了で書き込みが失われるのを防ぐ)
          event.waitUntil(caches.open(CACHE).then((c) => c.put(req, copy)));
        }
        return res;
      })
      .catch(() => caches.match(req, { ignoreSearch: true })),
  );
});
