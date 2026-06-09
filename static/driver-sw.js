const CACHE = 'driver-app-v4';

// Файлы оболочки приложения — кэшируются при установке
const SHELL = [
  '/driver/login',
  '/static/driver-manifest.json',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // API-запросы и POST — всегда в сеть, без кэша
  if (url.pathname.startsWith('/driver/api') || e.request.method !== 'GET') {
    return;
  }

  // Страницы приложения: сеть → кэш → офлайн-заглушка
  if (url.pathname.startsWith('/driver')) {
    e.respondWith(
      fetch(e.request)
        .then(res => {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, clone));
          return res;
        })
        .catch(() => caches.match(e.request).then(r => r || offlinePage()))
    );
    return;
  }

  // Статика — кэш → сеть
  if (url.pathname.startsWith('/static')) {
    e.respondWith(
      caches.match(e.request).then(r => r || fetch(e.request).then(res => {
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return res;
      }))
    );
  }
});

// ── Push notifications ────────────────────────────────────────────────────────
self.addEventListener('push', e => {
  let data = {};
  try { data = e.data ? e.data.json() : {}; } catch(_) {}
  const title = data.title || '🚖 Новый заказ!';
  const options = {
    body:              data.body || 'Откройте приложение, чтобы принять заказ',
    icon:              '/static/img/notif-icon.png',
    badge:             '/static/img/badge.png',
    vibrate:           [300, 100, 300, 100, 300],
    requireInteraction: true,
    tag:               data.tag || 'kt',     // одинаковый тег → одно уведомление, а не куча
    renotify:          true,                 // обновление снова всплывает сверху
    data:              { url: data.url || '/driver/' },
    actions: [
      { action: 'open', title: '📋 Открыть' },
    ],
  };
  e.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/driver/';
  e.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      for (const c of list) {
        if (c.url.includes('/driver') && 'focus' in c) return c.focus();
      }
      return clients.openWindow(url);
    })
  );
});

function offlinePage() {
  return new Response(
    `<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8">
     <meta name="viewport" content="width=device-width,initial-scale=1">
     <title>Нет связи</title>
     <style>
       body{font-family:-apple-system,sans-serif;background:#0f1117;color:#e2e8f0;
            display:flex;align-items:center;justify-content:center;min-height:100vh;
            flex-direction:column;gap:16px;padding:20px;text-align:center;}
       .icon{font-size:60px;}
       h1{font-size:22px;font-weight:700;}
       p{font-size:16px;color:#64748b;line-height:1.6;}
       button{padding:14px 28px;background:#f5b800;color:#0f1117;border:none;
              border-radius:12px;font-size:17px;font-weight:700;cursor:pointer;margin-top:8px;}
     </style></head><body>
     <div class="icon">📶</div>
     <h1>Нет подключения</h1>
     <p>Проверьте интернет и попробуйте снова</p>
     <button onclick="location.reload()">Обновить</button>
     </body></html>`,
    { headers: { 'Content-Type': 'text/html; charset=utf-8' } }
  );
}
