/* ══════════════════════════════════════════════════════
   DISPATCHER PWA  ·  Казанское Такси
══════════════════════════════════════════════════════ */

let currentTab = 'new';
let prevNewCount = 0;
let refreshTimer  = null;
const REFRESH_MS  = 15000; // 15 секунд

// ── Инициализация ──────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  registerSW();
  switchTab('new');
  fetchData();
  startAutoRefresh();

  // Запрос разрешения на уведомления
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
  }
});

// ── Service Worker ─────────────────────────────────────
function registerSW() {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/static/sw.js').catch(() => {});
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
  renderStats(data);

  // Бейджи на табах
  setBadge('badge-new',       data.orders_new.length);
  setBadge('badge-accepted',  data.orders_accepted.length);

  // Уведомление о новом заказе
  const newCount = data.orders_new.length;
  if (newCount > prevNewCount && prevNewCount !== null) {
    notifyNewOrder(newCount - prevNewCount);
    // Пульсация на первой карточке
    const first = document.querySelector('#list-new .order-card');
    if (first) { first.classList.add('fresh'); setTimeout(() => first.classList.remove('fresh'), 7000); }
  }
  prevNewCount = newCount;
}

// ── Рендер заказов ────────────────────────────────────
function renderOrders(status, orders, containerId) {
  const el = document.getElementById(containerId);
  if (!el) return;

  // Счётчик секции
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
  const driver = o.driver_name  ? `<span class="meta-chip driver">🚗 ${o.driver_name}</span>` : '';
  const coords = o.has_coords   ? '' : '<span class="meta-chip" style="color:#f59e0b;">⚠️ без координат</span>';

  const comment = o.comment
    ? `<div class="order-comment">💬 ${escHtml(o.comment)}</div>`
    : '';

  let actions = '';
  if (status === 'new') {
    actions = `
      <div class="order-actions">
        <button class="action-btn btn-accept" onclick="updateStatus(${o.id},'accepted')">✓ Принять</button>
        <button class="action-btn btn-reset"  onclick="updateStatus(${o.id},'new')" title="Сброс" style="display:none">↩</button>
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
    return `
      <div class="driver-card">
        <div class="driver-avatar">🚗</div>
        <div class="driver-info">
          <div class="driver-name">${escHtml(d.name)}</div>
          <div class="driver-status ${st.level}">${st.label}</div>
        </div>
        <span class="driver-active-badge">активен</span>
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
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `status=${newStatus}`,
    });
    if (res.ok || res.redirected) {
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
  const btn   = document.getElementById('nav-'   + tab);
  if (panel) panel.classList.add('active');
  if (btn)   btn.classList.add('active');
}

// ── Уведомление ──────────────────────────────────────
function notifyNewOrder(count) {
  showToast(`🔵 ${count === 1 ? 'Новый заказ!' : `${count} новых заказа!`}`);

  if ('Notification' in window && Notification.permission === 'granted') {
    new Notification('Казанское Такси', {
      body: `${count === 1 ? 'Новый заказ' : count + ' новых заказа'} ожидает обработки`,
      icon: '/static/img/icon-192.png',
      badge: '/static/img/icon-192.png',
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
  el.textContent  = count;
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
