/* ══════════════════════════════════════════════════════
   TAXI MAP · Казанский район — Yandex Maps 2.1
══════════════════════════════════════════════════════ */

// Ограничивающий прямоугольник: Казанский + соседние районы
const BOUNDS = [[54.8, 66.5], [57.2, 71.5]];
const CENTER = [55.73, 69.23]; // Центр Казанского района

// Популярные населённые пункты
const PLACES = [
  { name: 'Казанское',     q: 'Казанское, Казанский район, Тюменская область' },
  { name: 'Ишим',          q: 'Ишим, Тюменская область' },
  { name: 'Новоселезнево', q: 'Новоселезнево, Казанский район, Тюменская область' },
  { name: 'Большие Ярки',  q: 'Большие Ярки, Казанский район, Тюменская область' },
  { name: 'Ильинка',       q: 'Ильинка, Казанский район, Тюменская область' },
  { name: 'Яровское',      q: 'Яровское, Казанский район, Тюменская область' },
];

// ── Состояние ──────────────────────────────────────────
let ymap       = null;
let placemarkA = null, placemarkB = null;
let pointA     = null, pointB = null; // { lat, lon, address }
let mode       = 'a';
let routeObj   = null;

let whenMode     = 'now';
let dateOffset   = 0;
let pickedHour   = 12;
let pickedMinute = 0;
let paymentMethod = 'cash';

// ══════════════════════════════════════════════════════
// ИНИЦИАЛИЗАЦИЯ
// ══════════════════════════════════════════════════════
ymaps.ready(function () {
  initMap();
  initAddressInputs();
  renderChips();
  renderDateChips();
  setMode('a');
});

function initMap() {
  ymap = new ymaps.Map('map-container', {
    center: CENTER,
    zoom: 10,
    controls: ['zoomControl'],
  }, {
    suppressMapOpenBlock: true,
    yandexMapDisablePoiInteractivity: true,
  });

  // Клик по карте — ставим точку
  ymap.events.add('click', function (e) {
    if (!mode) return;
    const coords = e.get('coords'); // [lat, lon]
    handleMapClick(coords[0], coords[1]);
  });
}

// ══════════════════════════════════════════════════════
// РЕЖИМ (a / b / null)
// ══════════════════════════════════════════════════════
function setMode(newMode) {
  mode = newMode;

  // Кнопки на карте
  const btnA = document.getElementById('btn-mode-a');
  const btnB = document.getElementById('btn-mode-b');
  if (btnA) { btnA.classList.remove('active-a', 'active-b'); }
  if (btnB) { btnB.classList.remove('active-a', 'active-b'); }
  if (newMode === 'a' && btnA) btnA.classList.add('active-a');
  if (newMode === 'b' && btnB) btnB.classList.add('active-b');

  // Кнопки ниже карты
  const tapA = document.getElementById('tap-btn-a');
  const tapB = document.getElementById('tap-btn-b');
  if (tapA) tapA.classList.toggle('tap-active-a', newMode === 'a');
  if (tapB) tapB.classList.toggle('tap-active-b', newMode === 'b');

  // Подсветка строк
  const fromRow = document.getElementById('from-row');
  const toRow   = document.getElementById('to-row');
  if (fromRow) fromRow.classList.toggle('addr-row-active', newMode === 'a');
  if (toRow)   toRow.classList.toggle('addr-row-active',   newMode === 'b');

  // Курсор карты
  if (ymap) {
    try {
      ymap.cursors.pop('crosshair');
      if (newMode) ymap.cursors.push('crosshair');
    } catch (_) {}
  }

  if (newMode === 'a') document.getElementById('search-from').focus();
  if (newMode === 'b') document.getElementById('search-to').focus();
}

// ══════════════════════════════════════════════════════
// КЛИК ПО КАРТЕ
// ══════════════════════════════════════════════════════
async function handleMapClick(lat, lon) {
  const capturedMode = mode;
  showRouteBadge('loading');

  const address = await reverseGeocode(lat, lon);

  if (capturedMode === 'a') placePointA(lat, lon, address);
  else if (capturedMode === 'b') placePointB(lat, lon, address);

  if (pointA && pointB) buildRoute();
  else hideRouteBadge();

  if (capturedMode === 'a' && !pointB) setMode('b');
  else if (capturedMode === 'b') setMode(null);
}

// ══════════════════════════════════════════════════════
// ТОЧКИ НА КАРТЕ
// ══════════════════════════════════════════════════════
function placePointA(lat, lon, address) {
  if (placemarkA) ymap.geoObjects.remove(placemarkA);
  pointA = { lat, lon, address };

  placemarkA = new ymaps.Placemark([lat, lon], { hintContent: 'Откуда' }, {
    iconLayout:      'default#image',
    iconImageHref:   makePinSVG('A', '#4F9EFF'),
    iconImageSize:   [32, 42],
    iconImageOffset: [-16, -42],
    draggable: true,
  });

  placemarkA.events.add('dragend', function () {
    const c = placemarkA.geometry.getCoordinates();
    reverseGeocode(c[0], c[1]).then(addr => {
      pointA = { lat: c[0], lon: c[1], address: addr };
      setInputVal('search-from', addr);
      checkAddressVagueness(addr);
      if (pointB) buildRoute();
    });
  });

  ymap.geoObjects.add(placemarkA);
  setInputVal('search-from', address);
  show('clear-a');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
}

function placePointB(lat, lon, address) {
  if (placemarkB) ymap.geoObjects.remove(placemarkB);
  pointB = { lat, lon, address };

  placemarkB = new ymaps.Placemark([lat, lon], { hintContent: 'Куда' }, {
    iconLayout:      'default#image',
    iconImageHref:   makePinSVG('B', '#F97316'),
    iconImageSize:   [32, 42],
    iconImageOffset: [-16, -42],
    draggable: true,
  });

  placemarkB.events.add('dragend', function () {
    const c = placemarkB.geometry.getCoordinates();
    reverseGeocode(c[0], c[1]).then(addr => {
      pointB = { lat: c[0], lon: c[1], address: addr };
      setInputVal('search-to', addr);
      checkAddressVagueness(addr);
      if (pointA) buildRoute();
    });
  });

  ymap.geoObjects.add(placemarkB);
  setInputVal('search-to', address);
  show('clear-b');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
}

function clearPoint(which) {
  if (which === 'a') {
    if (placemarkA) { ymap.geoObjects.remove(placemarkA); placemarkA = null; }
    pointA = null;
    setInputVal('search-from', '');
    hide('clear-a');
    setMode('a');
  } else {
    if (placemarkB) { ymap.geoObjects.remove(placemarkB); placemarkB = null; }
    pointB = null;
    setInputVal('search-to', '');
    hide('clear-b');
  }
  clearRouteData();
  updateChipStates();
}

function swapPoints() {
  const tmpA = pointA ? { ...pointA } : null;
  const tmpB = pointB ? { ...pointB } : null;
  if (placemarkA) { ymap.geoObjects.remove(placemarkA); placemarkA = null; }
  if (placemarkB) { ymap.geoObjects.remove(placemarkB); placemarkB = null; }
  pointA = null; pointB = null;
  if (tmpB) placePointA(tmpB.lat, tmpB.lon, tmpB.address);
  if (tmpA) placePointB(tmpA.lat, tmpA.lon, tmpA.address);
  if (pointA && pointB) buildRoute();
}

function resetAll() {
  clearPoint('a');
  clearPoint('b');
  hideRouteBadge();
  hideCommentHint();
}

// ══════════════════════════════════════════════════════
// МАРШРУТ
// ══════════════════════════════════════════════════════
function buildRoute() {
  if (!pointA || !pointB) return;
  if (routeObj) { ymap.geoObjects.remove(routeObj); routeObj = null; }
  showRouteBadge('loading');

  ymaps.route(
    [[pointA.lat, pointA.lon], [pointB.lat, pointB.lon]],
    { routingMode: 'auto', mapStateAutoApply: false }
  ).then(function (route) {

    // Золотая линия маршрута
    route.getPaths().each(function (path) {
      path.options.set({
        strokeColor:   '#F5B800',
        strokeWidth:   5,
        strokeOpacity: 0.88,
      });
    });

    // Прячем маркеры начала/конца маршрута (у нас свои)
    route.getWayPoints().each(function (wp) {
      wp.options.set({ visible: false });
    });

    routeObj = route;
    ymap.geoObjects.add(route);

    const km   = (route.getLength() / 1000).toFixed(1);
    const mins = Math.round(route.getDuration() / 60);
    showRouteBadge('info', `📍 ${km} км · ~${mins} мин`);

    // Подогнать карту под маршрут
    try {
      const bounds = route.getBounds();
      if (bounds) ymap.setBounds(bounds, { checkZoomRange: true, zoomMargin: 60 });
    } catch (_) {}

  }).catch(function () {
    hideRouteBadge();
  });
}

function clearRouteData() {
  if (routeObj) { ymap.geoObjects.remove(routeObj); routeObj = null; }
  hideRouteBadge();
}

// ══════════════════════════════════════════════════════
// ГЕОКОДИНГ
// ══════════════════════════════════════════════════════
async function reverseGeocode(lat, lon) {
  try {
    const res = await ymaps.geocode([lat, lon], { results: 1 });
    const obj = res.geoObjects.get(0);
    return obj ? obj.getAddressLine() : `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
  } catch (_) {
    return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
  }
}

async function geocodeQuery(query) {
  try {
    const res = await ymaps.geocode(query, {
      boundedBy:    BOUNDS,
      strictBounds: false,
      results:      1,
    });
    const obj = res.geoObjects.get(0);
    if (!obj) return null;
    const coords = obj.geometry.getCoordinates(); // [lat, lon]
    return { lat: coords[0], lon: coords[1], address: obj.getAddressLine() };
  } catch (_) {
    return null;
  }
}

// ══════════════════════════════════════════════════════
// ПОИСК / ПОДСКАЗКИ
// ══════════════════════════════════════════════════════
function getLocalMatches(query) {
  const q = query.toLowerCase().trim();
  return PLACES
    .filter(p => p.name.toLowerCase().includes(q))
    .map(p => ({ _isLocal: true, _localName: p.name, _localQuery: p.q, displayName: p.name }));
}

async function getSuggestions(query) {
  const local = getLocalMatches(query);

  try {
    const items = await ymaps.suggest(query + ', Тюменская область', {
      boundedBy:    BOUNDS,
      strictBounds: false,
      results:      7,
      highlight:    false,
    });
    // Убираем дубли с локальными
    const api = items.filter(i =>
      !local.some(l => i.displayName && i.displayName.includes(l._localName))
    );
    return [...local, ...api];
  } catch (_) {
    return local;
  }
}

// ══════════════════════════════════════════════════════
// ИНПУТЫ АДРЕСОВ
// ══════════════════════════════════════════════════════
function initAddressInputs() {
  setupInput('search-from', 'drop-from', 'a');
  setupInput('search-to',   'drop-to',   'b');
}

function setupInput(inputId, dropId, pointType) {
  const input = document.getElementById(inputId);
  const drop  = document.getElementById(dropId);
  let timer;

  input.addEventListener('focus', () => {
    setMode(pointType);
  });

  input.addEventListener('blur', () => {
    setTimeout(() => hideDrop(drop), 200);
  });

  input.addEventListener('input', () => {
    clearTimeout(timer);
    const q = input.value.trim();
    if (q.length < 2) { hideDrop(drop); return; }

    timer = setTimeout(async () => {
      const suggestions = await getSuggestions(q);
      renderDrop(drop, suggestions, async (item) => {
        hideDrop(drop);

        let lat, lon, addr;

        if (item._isLocal) {
          const r = await geocodeQuery(item._localQuery);
          if (!r) { showFormMsg('error', `Не удалось найти «${item._localName}»`); return; }
          lat = r.lat; lon = r.lon;
          addr = item._localName + ', Казанский район';
        } else {
          const r = await geocodeQuery(item.value || item.displayName);
          if (!r) { showFormMsg('error', 'Не удалось определить координаты адреса'); return; }
          lat = r.lat; lon = r.lon;
          addr = r.address || item.displayName;
        }

        if (pointType === 'a') {
          placePointA(lat, lon, addr);
          ymap.setCenter([lat, lon], 13);
          if (!pointB) setMode('b');
        } else {
          placePointB(lat, lon, addr);
          ymap.setCenter([lat, lon], 13);
          setMode(null);
        }

        if (pointA && pointB) buildRoute();
      });
    }, 280);
  });
}

function renderDrop(drop, items, onSelect) {
  drop.innerHTML = '';

  if (!items.length) {
    drop.innerHTML = '<div class="drop-no-result">Не найдено — попробуйте другой запрос</div>';
    drop.style.display = 'block';
    return;
  }

  items.forEach(item => {
    const div = document.createElement('div');
    div.className = 'drop-item' + (item._isLocal ? ' drop-item-local' : '');

    const icon = item._isLocal ? '🏘' : '📍';
    const main = item._isLocal ? item._localName : (item.displayName || item.value || '');
    const sub  = item._isLocal
      ? 'Казанский район'
      : (item.value && item.value !== main ? item.value : '');

    div.innerHTML =
      `<span class="drop-icon">${icon}</span>` +
      `<span><strong>${escHtml(main)}</strong>` +
      (sub ? `<span class="drop-sub">${escHtml(sub)}</span>` : '') +
      `</span>`;

    div.addEventListener('mousedown', e => { e.preventDefault(); onSelect(item); });
    drop.appendChild(div);
  });

  drop.style.display = 'block';
}

function hideDrop(drop) { if (drop) drop.style.display = 'none'; }

// ══════════════════════════════════════════════════════
// ЧИПЫ НАСЕЛЁННЫХ ПУНКТОВ
// ══════════════════════════════════════════════════════
function renderChips() {
  const row = document.getElementById('chips-row');
  if (!row) return;
  row.innerHTML = '';
  PLACES.forEach(place => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'chip';
    btn.textContent = place.name;
    btn.dataset.name = place.name;
    btn.onclick = () => selectChip(place);
    row.appendChild(btn);
  });
}

async function selectChip(place) {
  const chip = document.querySelector(`#chips-row .chip[data-name="${place.name}"]`);
  if (chip) chip.classList.add('chip-loading');

  const r = await geocodeQuery(place.q);
  if (chip) chip.classList.remove('chip-loading');

  if (!r) { showFormMsg('error', `Не удалось найти «${place.name}»`); return; }

  if (mode === 'b' || (pointA && !pointB)) {
    placePointB(r.lat, r.lon, place.name);
    setMode(null);
  } else {
    placePointA(r.lat, r.lon, place.name);
    if (!pointB) setMode('b');
  }

  ymap.setCenter([r.lat, r.lon], 12);
  if (pointA && pointB) buildRoute();
}

function updateChipStates() {
  document.querySelectorAll('#chips-row .chip').forEach(chip => {
    chip.classList.remove('chip-selected-a', 'chip-selected-b');
    const name = chip.dataset.name;
    if (pointA?.address?.includes(name)) chip.classList.add('chip-selected-a');
    if (pointB?.address?.includes(name)) chip.classList.add('chip-selected-b');
  });
}

// ══════════════════════════════════════════════════════
// МАРШРУТ-БЕЙДЖ
// ══════════════════════════════════════════════════════
function showRouteBadge(type, text) {
  const info    = document.getElementById('route-info');
  const loading = document.getElementById('route-loading');
  if (type === 'loading') {
    if (loading) loading.style.display = 'flex';
    if (info)    info.style.display    = 'none';
  } else {
    if (loading) loading.style.display = 'none';
    if (info && text) { info.textContent = text; info.style.display = 'flex'; }
  }
}

function hideRouteBadge() { hide('route-info'); hide('route-loading'); }

// ══════════════════════════════════════════════════════
// SVG-МАРКЕР (пин)
// ══════════════════════════════════════════════════════
function makePinSVG(label, color) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="42" viewBox="0 0 32 42">
    <path d="M16 0C7.16 0 0 7.16 0 16C0 28 16 42 16 42S32 28 32 16C32 7.16 24.84 0 16 0Z" fill="${color}"/>
    <circle cx="16" cy="16" r="9" fill="white" opacity="0.95"/>
    <text x="16" y="20" text-anchor="middle" font-family="-apple-system,sans-serif"
          font-size="11" font-weight="800" fill="${color}">${label}</text>
  </svg>`;
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
}

// ══════════════════════════════════════════════════════
// ВЫБОР ВРЕМЕНИ
// ══════════════════════════════════════════════════════
function setWhen(w) {
  whenMode = w;
  document.getElementById('tab-now').classList.toggle('active',   w === 'now');
  document.getElementById('tab-later').classList.toggle('active', w === 'later');
  document.getElementById('time-picker').style.display = w === 'later' ? 'block' : 'none';
}

function renderDateChips() {
  const container = document.getElementById('date-chips');
  if (!container) return;
  container.innerHTML = '';
  const weekdays = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
  const today = new Date();
  for (let i = 0; i < 7; i++) {
    const d = new Date(today);
    d.setDate(today.getDate() + i);
    const label = i === 0 ? 'Сегодня' : i === 1 ? 'Завтра' : weekdays[d.getDay()] + ' ' + d.getDate();
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'date-chip' + (i === 0 ? ' active' : '');
    btn.textContent = label;
    const idx = i;
    btn.onclick = () => pickDate(idx);
    container.appendChild(btn);
  }
}

function pickDate(offset) {
  dateOffset = offset;
  document.querySelectorAll('#date-chips .date-chip').forEach((c, i) => {
    c.classList.toggle('active', i === offset);
  });
}

function spinHour(delta) {
  pickedHour = (pickedHour + delta + 24) % 24;
  document.getElementById('spin-hour').textContent = String(pickedHour).padStart(2, '0');
}

function spinMin(delta) {
  const steps = [0, 15, 30, 45];
  const idx = steps.indexOf(pickedMinute);
  pickedMinute = steps[(idx + delta + steps.length) % steps.length];
  document.getElementById('spin-min').textContent = String(pickedMinute).padStart(2, '0');
}

function getScheduledAt() {
  if (whenMode === 'now') return null;
  const d = new Date();
  d.setDate(d.getDate() + dateOffset);
  d.setHours(pickedHour, pickedMinute, 0, 0);
  return d.toISOString();
}

// ══════════════════════════════════════════════════════
// ОПЛАТА
// ══════════════════════════════════════════════════════
function setPayment(method) {
  paymentMethod = method;
  document.getElementById('payment-method').value = method;
  document.getElementById('pay-cash').classList.toggle('active',     method === 'cash');
  document.getElementById('pay-transfer').classList.toggle('active', method === 'transfer');
}

// ══════════════════════════════════════════════════════
// ОТПРАВКА ЗАКАЗА
// ══════════════════════════════════════════════════════
async function submitOrder() {
  const phone       = document.getElementById('phone').value.trim();
  const comment     = document.getElementById('order-comment').value.trim();
  const fromAddress = pointA ? pointA.address : document.getElementById('search-from').value.trim();
  const toAddress   = pointB ? pointB.address : document.getElementById('search-to').value.trim();

  if (!phone)       { showFormMsg('error', 'Введите номер телефона'); return; }
  if (!fromAddress) { showFormMsg('error', 'Укажите откуда ехать — чип, поиск или точка на карте'); return; }
  if (!toAddress)   { showFormMsg('error', 'Укажите куда ехать — чип, поиск или точка на карте'); return; }

  const btn = document.getElementById('submit-btn');
  btn.disabled = true;
  btn.innerHTML = '<span class="mini-spinner"></span> Отправляем…';

  try {
    const res = await fetch('/order', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone,
        from_address: fromAddress,
        from_lat:     pointA ? pointA.lat : null,
        from_lon:     pointA ? pointA.lon : null,
        to_address:   toAddress,
        to_lat:       pointB ? pointB.lat : null,
        to_lon:       pointB ? pointB.lon : null,
        comment:      comment || null,
        payment:      paymentMethod,
        scheduled_at: getScheduledAt(),
      }),
    });

    const data = await res.json();
    if (data.success) {
      showFormMsg('success', `✅ Заказ #${data.order_id} принят! Ожидайте звонка диспетчера.`);
      resetAll();
      document.getElementById('phone').value = '';
      document.getElementById('order-comment').value = '';
      setWhen('now');
      setPayment('cash');
      hideCommentHint();
    } else {
      showFormMsg('error', data.error || 'Не удалось создать заказ');
    }
  } catch (_) {
    showFormMsg('error', 'Ошибка сети — проверьте соединение и попробуйте снова');
  } finally {
    btn.disabled = false;
    btn.innerHTML = 'Заказать поездку <span class="btn-arrow">→</span>';
  }
}

// ══════════════════════════════════════════════════════
// ОТЗЫВЫ
// ══════════════════════════════════════════════════════
async function submitReview() {
  const name = document.getElementById('review-name').value.trim();
  const text = document.getElementById('review-text').value.trim();
  if (!name || !text) { showReviewMsg('error', 'Заполните имя и текст отзыва'); return; }

  try {
    const res  = await fetch('/review', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, text }),
    });
    const data = await res.json();
    if (data.success) {
      showReviewMsg('success', '✅ Отзыв отправлен на проверку. Спасибо!');
      document.getElementById('review-name').value = '';
      document.getElementById('review-text').value = '';
    } else {
      showReviewMsg('error', data.error || 'Ошибка отправки');
    }
  } catch (_) {
    showReviewMsg('error', 'Ошибка сети');
  }
}

function showReviewMsg(type, text) {
  const el = document.getElementById('review-message');
  if (!el) return;
  el.textContent = text;
  el.className = `form-msg ${type}`;
  el.style.display = 'block';
}

// ══════════════════════════════════════════════════════
// ПОДСКАЗКА «АДРЕС ПРИБЛИЗИТЕЛЬНЫЙ»
// ══════════════════════════════════════════════════════
function checkAddressVagueness(address) {
  const hasStreet = /\b(ул|улица|пер|переулок|пр|проспект|шоссе|тракт|набережная|д\.|дом)\b/i.test(address);
  if (!hasStreet) showCommentHint(); else hideCommentHint();
}

function showCommentHint() {
  const el = document.getElementById('comment-hint');
  if (el) el.style.display = 'flex';
}

function hideCommentHint() {
  const el = document.getElementById('comment-hint');
  if (el) el.style.display = 'none';
}

// ══════════════════════════════════════════════════════
// HELPERS
// ══════════════════════════════════════════════════════
function show(id) { const el = document.getElementById(id); if (el) el.style.display = ''; }
function hide(id) { const el = document.getElementById(id); if (el) el.style.display = 'none'; }
function setInputVal(id, val) { const el = document.getElementById(id); if (el) el.value = val; }

function showFormMsg(type, text) {
  const el = document.getElementById('form-message');
  if (!el) return;
  el.textContent = text;
  el.className = `form-msg ${type}`;
  el.style.display = 'block';
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.style.display = 'none'; }, type === 'success' ? 9000 : 6000);
}

function escHtml(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
