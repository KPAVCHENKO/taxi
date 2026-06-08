/* ══════════════════════════════════════════════════════
   DISPATCHER PWA  ·  Казанское Такси
══════════════════════════════════════════════════════ */

let currentTab   = 'new';
let prevNewCount = 0;
let refreshTimer = null;
const REFRESH_MS = 15000;

// ── Инициализация ──────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  registerSW();
  switchTab('new');
  fetchData();
  startAutoRefresh();
  initPush();

  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
});

// ── Service Worker ─────────────────────────────────────
function registerSW() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  }
}

// ── Авто-обновление ───────────────────────────────────
function startAutoRefresh() {
  clearInterval(refreshTimer);
  refreshTimer = setInterval(fetchData, REFRESH_MS);
}

// ── Получение данных ──────────────────────────────────
async function fetchData() {
  const btn = document.getElementById('refresh-icon');
  if (btn) btn.classList.add('spinning');

  try {
    const res  = await fetch('/api/dispatcher');
    const data = await res.json();

    setOnline(true);
    renderAll(data);
    document.getElementById('last-update').textContent =
      'Обновлено: ' + new Date().toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

  } catch (e) {
    setOnline(false);
  } finally {
    if (btn) btn.classList.remove('spinning');
  }
}

function setOnline(online) {
  const dot = document.getElementById('status-dot');
  if (dot) dot.className = 'status-dot' + (online ? '' : ' offline');
}

// ── Рендер всего ─────────────────────────────────────
function renderAll(data) {
  renderOrders('new',       data.orders_new,       'list-new');
  renderOrders('accepted',  data.orders_accepted,  'list-accepted');
  renderOrders('completed', data.orders_completed, 'list-completed');
  renderDrivers(data.drivers, data.driver_statuses);
  renderLog(data.recent_log || []);
  renderStats(data);

  setBadge('badge-new',      data.orders_new.length);
  setBadge('badge-accepted', data.orders_accepted.length);

  const newCount = data.orders_new.length;
  if (newCount > prevNewCount && prevNewCount !== null) {
    notifyNewOrder(newCount - prevNewCount);
    const first = document.querySelector('#list-new .order-card');
    if (first) { first.classList.add('fresh'); setTimeout(() => first.classList.remove('fresh'), 7000); }
  }
  prevNewCount = newCount;
}

// ── Рендер заказов ────────────────────────────────────
function renderOrders(status, orders, containerId) {
  const el = document.getElementById(containerId);
  if (!el) return;

  const counter = document.getElementById('count-' + status);
  if (counter) counter.textContent = orders.length;

  if (!orders.length) {
    el.innerHTML = `<div class="empty"><div class="empty-icon">${status === 'new' ? '📭' : status === 'accepted' ? '🚖' : '✅'}</div><div class="empty-text">${status === 'new' ? 'Новых заказов нет' : status === 'accepted' ? 'Нет активных поездок' : 'Нет завершённых'}</div></div>`;
    return;
  }

  el.innerHTML = orders.map(o => orderCardHTML(o, status)).join('');
}

function orderCardHTML(o, status) {
  const pay    = o.payment === 'transfer' ? '<span class="meta-chip pay-transfer">📲 Перевод</span>' : '<span class="meta-chip">💵 Наличные</span>';
  const sched  = o.scheduled_at ? `<span class="meta-chip scheduled">🕐 ${o.scheduled_at}</span>` : '<span class="meta-chip">Сейчас</span>';
  const driver = o.driver_name  ? `<span class="meta-chip driver">🚗 ${escHtml(o.driver_name)}</span>` : '';
  const coords = o.has_coords   ? '' : '<span class="meta-chip" style="color:#f59e0b;">⚠️ без координат</span>';

  const comment = o.comment
    ? `<div class="order-comment">💬 ${escHtml(o.comment)}</div>`
    : '';

  let actions = '';
  if (status === 'new') {
    actions = `
      <div class="order-actions">
        <button class="action-btn btn-accept" onclick="updateStatus(${o.id},'accepted')">✓ Принять</button>
      </div>`;
  } else if (status === 'accepted') {
    actions = `
      <div class="order-actions">
        <button class="action-btn btn-complete" onclick="updateStatus(${o.id},'completed')">✓ Завершить</button>
        <button class="action-btn btn-reset"    onclick="updateStatus(${o.id},'new')">↩ Сброс</button>
      </div>`;
  }

  const phoneBlock = status !== 'new'
    ? `<div class="order-phone"><a class="phone-link" href="tel:${escHtml(o.phone)}">📞 ${escHtml(o.phone)}</a></div>`
    : `<div class="order-phone" style="color:var(--tm); font-size:13px;">📞 Скрыт до принятия</div>`;

  return `
    <div class="order-card status-${status}" id="order-${o.id}">
      <div class="order-card-head">
        <div>
          <div class="order-id">#${o.id}</div>
          <span class="order-badge badge-${status}">${statusLabel(status)}</span>
        </div>
        <div class="order-time">${o.created_at}</div>
      </div>
      <div class="order-route">
        <div class="route-from"><span class="route-dot dot-a"></span><span class="route-addr">${escHtml(o.from_address)}</span></div>
        <div class="route-to"  style="margin-top:4px;"><span class="route-dot dot-b"></span><span class="route-addr">${escHtml(o.to_address)}</span></div>
      </div>
      ${comment}
      <div class="order-meta">${pay}${sched}${driver}${coords}</div>
      ${phoneBlock}
      ${actions}
    </div>`;
}

function statusLabel(s) {
  return s === 'new' ? '🔵 Новый' : s === 'accepted' ? '🟢 В работе' : '⚫ Завершён';
}

// ── Рендер водителей ──────────────────────────────────
function renderDrivers(drivers, statuses) {
  const el = document.getElementById('list-drivers');
  if (!el) return;

  if (!drivers.length) {
    el.innerHTML = '<div class="empty"><div class="empty-icon">🚗</div><div class="empty-text">Нет активных водителей</div></div>';
    return;
  }

  el.innerHTML = drivers.map(d => {
    const st = statuses[d.id] || { label: 'Свободен', level: 'free' };
    const phoneHtml = d.phone
      ? `<div style="font-size:12px;margin-top:3px;"><a href="tel:${escHtml(d.phone)}" style="color:#7dd3fc;text-decoration:none;">📞 ${escHtml(d.phone)}</a></div>`
      : '';
    const carHtml = d.car_info
      ? `<div style="font-size:11px;color:#64748b;margin-top:2px;">🚗 ${escHtml(d.car_info)}</div>`
      : '';
    return `
      <div class="driver-card">
        <div class="driver-avatar">🚗</div>
        <div class="driver-info">
          <div class="driver-name">${escHtml(d.name)}</div>
          <div class="driver-status ${st.level}">${st.label}</div>
          ${phoneHtml}
          ${carHtml}
        </div>
        <span class="driver-active-badge">активен</span>
      </div>`;
  }).join('');
}

// ── Рендер лога ───────────────────────────────────────
const LOG_LABELS = {
  'order_created':    '📦 Заказ создан',
  'order_assigned':   '📋 Назначен водитель',
  'status_changed':   '🔄 Статус изменён',
  'driver_accepted':  '✅ Принят водителем',
  'driver_cancelled': '❌ Отменён водителем',
  'driver_added':     '➕ Водитель добавлен',
  'driver_updated':   '✏️ Водитель изменён',
  'driver_deleted':   '🗑 Водитель удалён',
  'tariff_added':     '💰 Тариф добавлен',
  'tariff_updated':   '💰 Тариф изменён',
  'tariff_deleted':   '💰 Тариф удалён',
};

function renderLog(entries) {
  const el = document.getElementById('list-log');
  if (!el) return;

  if (!entries.length) {
    el.innerHTML = '<div class="empty"><div class="empty-icon">📜</div><div class="empty-text">Лог пуст</div></div>';
    return;
  }

  el.innerHTML = entries.map(e => {
    const label   = LOG_LABELS[e.action] || e.action;
    const orderBadge = e.order_id
      ? `<span style="font-size:11px;color:#a78bfa;margin-left:6px;">#${e.order_id}</span>` : '';
    const details = e.details
      ? `<div style="font-size:11px;color:#64748b;margin-top:3px;">${escHtml(e.details)}</div>` : '';
    return `
      <div style="display:flex;gap:10px;padding:10px 16px;border-bottom:1px solid rgba(255,255,255,0.05);align-items:flex-start;">
        <div style="font-size:11px;color:#475569;white-space:nowrap;margin-top:2px;">${e.created_at}</div>
        <div style="flex:1;">
          <div style="font-size:13px;font-weight:600;color:#e2e8f0;">${label}${orderBadge}</div>
          <div style="font-size:12px;color:#64748b;">${escHtml(e.actor || '')}</div>
          ${details}
        </div>
      </div>`;
  }).join('');
}

// ── Статистика ────────────────────────────────────────
function renderStats(data) {
  setText('stat-new',       data.orders_new.length);
  setText('stat-accepted',  data.orders_accepted.length);
  setText('stat-today',     data.today_count);
  setText('stat-drivers',   data.active_drivers);
}

// ── Действие: изменить статус заказа ─────────────────
async function updateStatus(orderId, newStatus) {
  try {
    const res = await fetch(`/admin/orders/${orderId}/status`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: `status=${newStatus}`,
    });
    if (res.ok) {
      showToast(newStatus === 'accepted' ? '✅ Заказ принят' : newStatus === 'completed' ? '✓ Завершён' : '↩ Сброшен');
      await fetchData();
    }
  } catch (e) {
    showToast('Ошибка сети');
  }
}

// ── Переключение вкладок ──────────────────────────────
function switchTab(tab) {
  currentTab = tab;
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-tab').forEach(b => b.classList.remove('active'));

  const panel = document.getElementById('panel-' + tab);
  const btn   = document.getElementById('nav-' + tab);
  if (panel) panel.classList.add('active');
  if (btn)   btn.classList.add('active');
}

// ── Уведомление ──────────────────────────────────────
function notifyNewOrder(count) {
  showToast(`🔵 ${count === 1 ? 'Новый заказ!' : `${count} новых заказа!`}`);

  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification('Казанское Такси', {
      body: `${count === 1 ? 'Новый заказ' : count + ' новых заказа'} ожидает обработки`,
      icon: '/static/img/notif-icon.png',
      badge: '/static/img/badge.png',
      vibrate: [200, 100, 200],
    });
  }

  if ('vibrate' in navigator) navigator.vibrate([150, 50, 150]);
}

// ── Ручное обновление ─────────────────────────────────
function manualRefresh() {
  clearInterval(refreshTimer);
  fetchData();
  startAutoRefresh();
}

// ── Toast ─────────────────────────────────────────────
let toastTimer;
function showToast(msg) {
  const t = document.getElementById('toast');
  if (!t) return;
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2800);
}

// ── Helpers ───────────────────────────────────────────
function setBadge(id, count) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent   = count;
  el.style.display = count > 0 ? 'flex' : 'none';
}

function setText(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val;
}

function escHtml(s) {
  return String(s ?? '')
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Push-уведомления ──────────────────────────────────
let pushSubscription = null;

async function initPush() {
  try {
    const res  = await fetch('/api/push/vapid-public-key');
    const data = await res.json();
    if (!data.enabled || !data.key) {
      const el = document.getElementById('push-btn');
      if (el) el.style.display = 'none';
      return;
    }
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      const el = document.getElementById('push-btn');
      if (el) el.style.display = 'none';
      return;
    }
    const reg = await navigator.serviceWorker.ready;
    pushSubscription = await reg.pushManager.getSubscription();
    updatePushBtn();
  } catch (e) {
    console.warn('Push init error:', e);
  }
}

function updatePushBtn() {
  const btn = document.getElementById('push-btn');
  if (!btn) return;
  if (pushSubscription) {
    btn.textContent      = '🔔 Уведомления вкл';
    btn.style.background = 'rgba(52,211,153,0.2)';
    btn.style.color      = '#34d399';
    btn.style.borderColor = 'rgba(52,211,153,0.3)';
  } else {
    btn.textContent      = '🔕 Включить уведомления';
    btn.style.background = 'rgba(124,111,255,0.15)';
    btn.style.color      = '#a78bfa';
    btn.style.borderColor = 'rgba(124,111,255,0.3)';
  }
}

async function togglePush() {
  try {
    if (pushSubscription) {
      await fetch('/api/push/unsubscribe', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ endpoint: pushSubscription.endpoint }),
      });
      await pushSubscription.unsubscribe();
      pushSubscription = null;
    } else {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') {
        alert('Разрешите уведомления в браузере');
        return;
      }
      const keyRes  = await fetch('/api/push/vapid-public-key');
      const keyData = await keyRes.json();
      const reg     = await navigator.serviceWorker.ready;
      pushSubscription = await reg.pushManager.subscribe({
        userVisibleOnly:      true,
        applicationServerKey: urlBase64ToUint8Array(keyData.key),
      });
      await fetch('/api/push/subscribe', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(pushSubscription.toJSON()),
      });
    }
    updatePushBtn();
  } catch (e) {
    console.error('Push error:', e);
    alert('Ошибка: ' + e.message);
  }
}

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - base64String.length % 4) % 4);
  const base64  = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  return Uint8Array.from([...rawData].map(c => c.charCodeAt(0)));
}
