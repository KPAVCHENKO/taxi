const CACHE = 'client-app-v1';

const PRECACHE = [
  '/',
  '/static/css/style.css',
  '/static/img/icon-192.png',
  '/static/img/icon-512.png',
  '/api/tariffs',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(PRECACHE).catch(() => {}))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // POST и API заказа — всегда в сеть
  if (e.request.method !== 'GET' || url.pathname === '/order') return;

  // Тарифы — кэш + обновление в фоне
  if (url.pathname === '/api/tariffs') {
    e.respondWith(
      caches.open(CACHE).then(c =>
        c.match(e.request).then(cached => {
          const fresh = fetch(e.request).then(res => { c.put(e.request, res.clone()); return res; });
          return cached || fresh;
        })
      )
    );
    return;
  }

  // Главная и статика — сеть → кэш → офлайн
  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then(r => r || offlinePage()))
  );
});

function offlinePage() {
  return new Response(
    `<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
     <meta name="viewport" content="width=device-width,initial-scale=1">
     <title>Нет связи — Казанское Такси</title>
     <style>
       body{font-family:-apple-system,sans-serif;background:#1E2535;color:#fff;
            display:flex;align-items:center;justify-content:center;
            min-height:100vh;flex-direction:column;gap:16px;padding:20px;text-align:center;}
       .icon{font-size:64px;}
       h1{font-size:22px;font-weight:700;color:#F5B800;}
       p{font-size:16px;color:#C2CEDF;line-height:1.6;max-width:320px;}
       a{display:block;margin-top:8px;padding:14px 32px;background:#F5B800;color:#1E2535;
         border-radius:12px;font-size:17px;font-weight:700;text-decoration:none;}
       button{padding:14px 28px;background:rgba(255,255,255,0.1);color:#fff;border:1px solid rgba(255,255,255,0.2);
              border-radius:12px;font-size:16px;font-weight:600;cursor:pointer;}
     </style></head><body>
     <div class="icon">🚖</div>
     <h1>Нет подключения</h1>
     <p>Для заказа онлайн нужен интернет. Вы можете позвонить нам напрямую.</p>
     <a href="tel:+79630608419">📞 8-963-060-84-19</a>
     <button onclick="location.reload()" style="margin-top:8px;">Попробовать снова</button>
     </body></html>`,
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}
