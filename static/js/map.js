/* ══════════════════════════════════════════════════════════════
   TAXI MAP · Казанский район, Тюменская область
   MapLibre GL JS + Geoapify
══════════════════════════════════════════════════════════════ */

// ── Константы ──────────────────────────────────────────────────────────────
const GEOAPIFY_KEY = window.GEOAPIFY_KEY;

// Центр Казанского района (lon, lat)
const CENTER_LON = 69.23;
const CENTER_LAT = 55.73;

// Поиск строго по 4 ближайшим районам:
// Казанский, Бердюжский, Сладковский, Ишимский
// rect: lon_min, lat_min, lon_max, lat_max
const GEO_FILTER = 'rect:66.5,54.8,71.5,57.2';
const GEO_BIAS   = `proximity:${CENTER_LON},${CENTER_LAT}`;

// Популярные населённые пункты — всегда показываются в поиске
// q — запрос для геокодинга с максимальным контекстом
const PLACES = [
  { name: 'Казанское',        q: 'Казанское, Казанский район, Тюменская область, Россия' },
  { name: 'Ишим',             q: 'Ишим, Тюменская область, Россия' },
  { name: 'Новоселезнево',    q: 'Новоселезнево, Казанский район, Тюменская область, Россия' },
  { name: 'Большие Ярки',     q: 'Большие Ярки, Казанский район, Тюменская область, Россия' },
  { name: 'Ильинка',          q: 'Ильинка, Казанский район, Тюменская область, Россия' },
  { name: 'Яровское',         q: 'Яровское, Казанский район, Тюменская область, Россия' },
];

// ── Состояние ─────────────────────────────────────────────────────────────
let map      = null;
let mapReady = false;
let markerA  = null;
let markerB  = null;
let pointA   = null;   // { lat, lng, address }
let pointB   = null;
let mode     = null;   // 'a' | 'b' | null

// Какой инпут сейчас активен (для чипов)
let activeInput = null;  // 'a' | 'b'

// Время
let whenMode        = 'now';
let dateOffset      = 0;   // 0=сегодня, 1=завтра, 2=послезавтра
let pickedHour      = 12;
let pickedMinute    = 0;

// ── Инициализация ─────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initMap();
  initAddressInputs();
  renderChips();
});

// ══════════════════════════════════════════════════════════════
// КАРТА
// ══════════════════════════════════════════════════════════════
function initMap() {
  map = new maplibregl.Map({
    container: 'map-container',
    style: `https://maps.geoapify.com/v1/styles/osm-bright/style.json?apiKey=${GEOAPIFY_KEY}`,
    center: [CENTER_LON, CENTER_LAT],
    zoom: 10,
  });

  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

  map.on('load', () => {
    map.addSource('route', { type: 'geojson', data: emptyGeoJSON() });

    // Белая обводка маршрута
    map.addLayer({
      id: 'route-outline',
      type: 'line',
      source: 'route',
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: { 'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.6 },
    });

    // Синяя линия маршрута
    map.addLayer({
      id: 'route-line',
      type: 'line',
      source: 'route',
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: { 'line-color': '#2563EB', 'line-width': 4 },
    });

    mapReady = true;
  });

  // Клик по карте
  map.on('click', (e) => {
    if (!mode) return;
    const { lng, lat } = e.lngLat;
    handleMapClick(lat, lng);
  });

  map.on('mousemove', () => {
    if (map) map.getCanvas().style.cursor = mode ? 'crosshair' : '';
  });
}

// ══════════════════════════════════════════════════════════════
// РЕЖИМ (A / B / null)
// ══════════════════════════════════════════════════════════════
function setMode(newMode) {
  mode = newMode;
  activeInput = newMode;

  const btnA = document.getElementById('btn-mode-a');
  const btnB = document.getElementById('btn-mode-b');

  btnA.classList.remove('active-a', 'active-b');
  btnB.classList.remove('active-a', 'active-b');

  if (newMode === 'a') btnA.classList.add('active-a');
  if (newMode === 'b') btnB.classList.add('active-b');

  if (map) map.getCanvas().style.cursor = newMode ? 'crosshair' : '';

  // Фокусируем нужный инпут
  if (newMode === 'a') document.getElementById('search-from').focus();
  if (newMode === 'b') document.getElementById('search-to').focus();
}

// ══════════════════════════════════════════════════════════════
// КЛИК ПО КАРТЕ
// ══════════════════════════════════════════════════════════════
async function handleMapClick(lat, lng) {
  const capturedMode = mode;
  showRouteBadge('loading');

  const address = await reverseGeocode(lat, lng);

  if (capturedMode === 'a') {
    placePointA(lat, lng, address);
  } else if (capturedMode === 'b') {
    placePointB(lat, lng, address);
  }

  if (pointA && pointB) {
    buildRoute();
  } else {
    hideRouteBadge();
  }

  // После A — автоматически переключаем в режим B
  if (capturedMode === 'a' && !pointB) {
    setMode('b');
  } else if (capturedMode === 'b') {
    setMode(null);
  }
}

// ══════════════════════════════════════════════════════════════
// УСТАНОВКА ТОЧЕК
// ══════════════════════════════════════════════════════════════
function placePointA(lat, lng, address) {
  if (markerA) { markerA.remove(); markerA = null; }
  pointA = { lat, lng, address };

  markerA = new maplibregl.Marker({ element: makeMarkerEl('A', '#2563EB') })
    .setLngLat([lng, lat])
    .addTo(map);

  setInputVal('search-from', address);
  show('clear-a');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
}

function placePointB(lat, lng, address) {
  if (markerB) { markerB.remove(); markerB = null; }
  pointB = { lat, lng, address };

  markerB = new maplibregl.Marker({ element: makeMarkerEl('B', '#F97316') })
    .setLngLat([lng, lat])
    .addTo(map);

  setInputVal('search-to', address);
  show('clear-b');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
}

function clearPoint(which) {
  if (which === 'a') {
    if (markerA) { markerA.remove(); markerA = null; }
    pointA = null;
    setInputVal('search-from', '');
    hide('clear-a');
  } else {
    if (markerB) { markerB.remove(); markerB = null; }
    pointB = null;
    setInputVal('search-to', '');
    hide('clear-b');
  }
  clearRouteData();
  updateChipStates();
}

function swapPoints() {
  const tmpA = pointA;
  const tmpB = pointB;

  // Убираем маркеры
  if (markerA) { markerA.remove(); markerA = null; }
  if (markerB) { markerB.remove(); markerB = null; }
  pointA = null;
  pointB = null;

  // Расставляем в обратном порядке
  if (tmpB) placePointA(tmpB.lat, tmpB.lng, tmpB.address);
  if (tmpA) placePointB(tmpA.lat, tmpA.lng, tmpA.address);

  clearRouteData();
  if (pointA && pointB) buildRoute();
}

function resetAll() {
  if (markerA) { markerA.remove(); markerA = null; }
  if (markerB) { markerB.remove(); markerB = null; }
  pointA = null;
  pointB = null;

  setInputVal('search-from', '');
  setInputVal('search-to', '');
  hide('clear-a');
  hide('clear-b');

  closeAllDropdowns();
  clearRouteData();
  updateChipStates();
  setMode(null);

  map.flyTo({ center: [CENTER_LON, CENTER_LAT], zoom: 10, duration: 600 });
}

// ══════════════════════════════════════════════════════════════
// МАРКЕР
// ══════════════════════════════════════════════════════════════
function makeMarkerEl(label, color) {
  const el = document.createElement('div');
  el.className = 'map-marker';
  el.style.backgroundColor = color;

  const lbl = document.createElement('div');
  lbl.className = 'map-marker-label';
  lbl.textContent = label;

  el.appendChild(lbl);
  return el;
}

// ══════════════════════════════════════════════════════════════
// ГЕОКОДИНГ
// ══════════════════════════════════════════════════════════════
async function reverseGeocode(lat, lon) {
  try {
    const url = new URL('https://api.geoapify.com/v1/geocode/reverse');
    url.searchParams.set('lat',    lat);
    url.searchParams.set('lon',    lon);
    url.searchParams.set('lang',   'ru');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();

    if (data.features && data.features.length > 0) {
      return data.features[0].properties.formatted
          || `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
    }
  } catch (e) { /* тихо */ }
  return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
}

// Геокодинг с максимальным контекстом для конкретного запроса (чипы)
async function geocodeExact(query) {
  try {
    const url = new URL('https://api.geoapify.com/v1/geocode/search');
    url.searchParams.set('text',    query);
    url.searchParams.set('lang',    'ru');
    url.searchParams.set('limit',   '1');
    url.searchParams.set('bias',    GEO_BIAS);
    url.searchParams.set('apiKey',  GEOAPIFY_KEY);
    const res  = await fetch(url.toString());
    const data = await res.json();
    return data.features || [];
  } catch (e) { return []; }
}

// Геокодинг для текстового поиска — строгий фильтр по 4 районам
async function searchAddress(query) {
  if (!query || query.trim().length < 2) return [];
  try {
    const url = new URL('https://api.geoapify.com/v1/geocode/search');
    url.searchParams.set('text',   query.trim());
    url.searchParams.set('filter', GEO_FILTER);
    url.searchParams.set('bias',   GEO_BIAS);
    url.searchParams.set('lang',   'ru');
    url.searchParams.set('limit',  '6');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();
    return data.features || [];
  } catch (e) { return []; }
}

// Объединяем локальные совпадения + API результаты
// Локальные всегда показываются первыми (даже если Geoapify их не знает)
function getLocalMatches(query) {
  const q = query.toLowerCase().trim();
  return PLACES.filter(p => p.name.toLowerCase().includes(q));
}

async function getSearchSuggestions(query) {
  if (!query || query.trim().length < 2) return [];

  const localMatches = getLocalMatches(query);
  const [apiFeatures] = await Promise.all([searchAddress(query)]);

  // Превращаем локальные совпадения в «виртуальные» фичи
  const localFeatures = localMatches.map(p => ({
    _isLocal: true,
    _localName: p.name,
    _localQuery: p.q,
  }));

  // API-результаты — убираем те, что совпадают с локальными по названию
  const filteredApi = apiFeatures.filter(f => {
    const addr = (f.properties.formatted || '').toLowerCase();
    return !localMatches.some(p => addr.includes(p.name.toLowerCase()));
  });

  return [...localFeatures, ...filteredApi].slice(0, 7);
}

// ══════════════════════════════════════════════════════════════
// АВТОДОПОЛНЕНИЕ
// ══════════════════════════════════════════════════════════════
function initAddressInputs() {
  setupInput('search-from', 'a', 'drop-from');
  setupInput('search-to',   'b', 'drop-to');
}

function setupInput(inputId, pointType, dropId) {
  const input = document.getElementById(inputId);
  const drop  = document.getElementById(dropId);
  if (!input || !drop) return;

  let timer;

  input.addEventListener('focus', () => {
    activeInput = pointType;
    highlightRow(pointType, true);
  });

  input.addEventListener('blur', () => {
    highlightRow(pointType, false);
    setTimeout(() => hideDrop(drop), 200);
  });

  input.addEventListener('input', () => {
    clearTimeout(timer);
    const q = input.value.trim();

    if (q.length < 2) { hideDrop(drop); return; }

    timer = setTimeout(async () => {
      const suggestions = await getSearchSuggestions(q);

      renderDrop(drop, suggestions, async (item) => {
        hideDrop(drop);

        let lat, lon, addr;

        if (item._isLocal) {
          // Локальная подсказка — геокодируем через точный запрос
          const features = await geocodeExact(item._localQuery);
          if (!features.length) {
            showFormMsg('error', `Не удалось найти "${item._localName}"`);
            return;
          }
          lat  = features[0].properties.lat;
          lon  = features[0].properties.lon;
          addr = features[0].properties.formatted || item._localName;
        } else {
          lat  = item.properties.lat;
          lon  = item.properties.lon;
          addr = item.properties.formatted || '';
        }

        if (pointType === 'a') {
          placePointA(lat, lon, addr);
          map.flyTo({ center: [lon, lat], zoom: 13 });
          if (!pointB) setMode('b');
        } else {
          placePointB(lat, lon, addr);
          map.flyTo({ center: [lon, lat], zoom: 13 });
          setMode(null);
        }

        if (pointA && pointB) buildRoute();
      });
    }, 280);
  });

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') hideDrop(drop);
  });
}

function renderDrop(drop, suggestions, onSelect) {
  drop.innerHTML = '';

  if (!suggestions.length) {
    drop.innerHTML = '<div class="drop-no-result">Ничего не найдено — попробуйте другой запрос</div>';
    drop.style.display = 'block';
    return;
  }

  suggestions.forEach((item) => {
    const el   = document.createElement('div');
    el.className = 'drop-item';

    const icon  = document.createElement('span');
    icon.className = 'drop-icon';

    const label = document.createElement('span');

    if (item._isLocal) {
      // Локальная подсказка (наш населённый пункт)
      icon.textContent  = '🏘';
      label.innerHTML   = `<strong>${item._localName}</strong>
        <span class="drop-sub">Казанский район, Тюменская область</span>`;
      el.classList.add('drop-item-local');
    } else {
      icon.textContent = '📍';
      label.textContent = item.properties.formatted || '';
    }

    el.appendChild(icon);
    el.appendChild(label);

    el.addEventListener('mousedown', (e) => {
      e.preventDefault();
      onSelect(item);
    });

    drop.appendChild(el);
  });

  drop.style.display = 'block';
}

function hideDrop(drop) {
  if (drop) { drop.style.display = 'none'; drop.innerHTML = ''; }
}

function closeAllDropdowns() {
  hideDrop(document.getElementById('drop-from'));
  hideDrop(document.getElementById('drop-to'));
}

function highlightRow(type, on) {
  const row = document.getElementById(type === 'a' ? 'from-row' : 'to-row');
  if (!row) return;
  if (on) {
    row.style.background = type === 'a' ? '#EFF6FF' : '#FFF7ED';
  } else {
    row.style.background = '';
  }
}

// ══════════════════════════════════════════════════════════════
// ЧИПЫ НАСЕЛЁННЫХ ПУНКТОВ
// ══════════════════════════════════════════════════════════════
function renderChips() {
  const row = document.getElementById('chips-row');
  if (!row) return;

  PLACES.forEach((place) => {
    const btn = document.createElement('button');
    btn.className   = 'chip';
    btn.textContent = place.name;
    btn.dataset.name = place.name;

    btn.addEventListener('click', () => onChipClick(place, btn));
    row.appendChild(btn);
  });
}

async function onChipClick(place, btn) {
  // Определяем цель: A или B
  const target = resolveChipTarget();

  btn.classList.add('chip-loading');
  btn.disabled = true;

  const features = await geocodeExact(place.q);

  btn.classList.remove('chip-loading');
  btn.disabled = false;

  if (!features.length) {
    showFormMsg('error', `Не удалось найти "${place.name}" — попробуйте ввести вручную`);
    return;
  }

  const { lat, lon, formatted } = features[0].properties;
  const addr = formatted || place.name;

  if (target === 'a') {
    placePointA(lat, lon, addr);
    map.flyTo({ center: [lon, lat], zoom: 12 });
    if (!pointB) setMode('b');
  } else {
    placePointB(lat, lon, addr);
    map.flyTo({ center: [lon, lat], zoom: 12 });
    setMode(null);
  }

  if (pointA && pointB) buildRoute();
}

function resolveChipTarget() {
  // Если есть активный инпут — используем его
  if (activeInput) return activeInput;
  // Иначе: заполняем A первым, потом B
  if (!pointA) return 'a';
  if (!pointB) return 'b';
  return 'b';
}

function updateChipStates() {
  const chips = document.querySelectorAll('#chips-row .chip');
  chips.forEach((chip) => {
    chip.classList.remove('chip-selected-a', 'chip-selected-b');
    const name = chip.dataset.name;
    if (pointA && pointA.address && pointA.address.includes(name)) {
      chip.classList.add('chip-selected-a');
    }
    if (pointB && pointB.address && pointB.address.includes(name)) {
      chip.classList.add('chip-selected-b');
    }
  });
}

// ══════════════════════════════════════════════════════════════
// МАРШРУТ
// ══════════════════════════════════════════════════════════════
async function buildRoute() {
  if (!pointA || !pointB || !mapReady) return;

  showRouteBadge('loading');

  try {
    const url = new URL('https://api.geoapify.com/v1/routing');
    // Geoapify routing: lat,lon порядок (не lon,lat!)
    url.searchParams.set('waypoints', `${pointA.lat},${pointA.lng}|${pointB.lat},${pointB.lng}`);
    url.searchParams.set('mode',   'drive');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();

    if (data.features && data.features.length > 0) {
      map.getSource('route').setData(data);

      const props  = data.features[0].properties;
      const km     = (props.distance / 1000).toFixed(1);
      const mins   = Math.round(props.time / 60);
      showRouteBadge('info', `📍 ${km} км · ~${mins} мин`);

      fitBounds(data.features[0].geometry);
    } else {
      showRouteBadge('info', 'Маршрут не построен');
    }
  } catch (e) {
    console.error('[route]', e);
    hideRouteBadge();
  }
}

function fitBounds(geometry) {
  let coords = [];
  if (geometry.type === 'MultiLineString') {
    geometry.coordinates.forEach((line) => coords.push(...line));
  } else if (geometry.type === 'LineString') {
    coords = geometry.coordinates;
  }
  if (!coords.length) return;

  const bounds = new maplibregl.LngLatBounds();
  coords.forEach((c) => bounds.extend(c));
  map.fitBounds(bounds, { padding: 60, maxZoom: 14, duration: 700 });
}

function clearRouteData() {
  if (mapReady && map.getSource('route')) {
    map.getSource('route').setData(emptyGeoJSON());
  }
  hideRouteBadge();
}

function showRouteBadge(type, text) {
  const info    = document.getElementById('route-info');
  const loading = document.getElementById('route-loading');

  if (type === 'loading') {
    if (loading) loading.style.display = 'flex';
    if (info)    info.style.display    = 'none';
  } else {
    if (loading) loading.style.display = 'none';
    if (info && text) {
      info.textContent = text;
      info.style.display = 'flex';
    }
  }
}

function hideRouteBadge() {
  hide('route-info');
  hide('route-loading');
}

// ══════════════════════════════════════════════════════════════
// ВЫБОР ВРЕМЕНИ
// ══════════════════════════════════════════════════════════════
function setWhen(mode) {
  whenMode = mode;

  const tabNow   = document.getElementById('tab-now');
  const tabLater = document.getElementById('tab-later');
  const picker   = document.getElementById('time-picker');

  tabNow.classList.toggle('active',   mode === 'now');
  tabLater.classList.toggle('active', mode === 'later');
  picker.style.display = mode === 'later' ? 'block' : 'none';
}

function pickDate(offset) {
  dateOffset = offset;
  document.querySelectorAll('.date-chip').forEach((chip, i) => {
    chip.classList.toggle('active', i === offset);
  });
}

function spinHour(delta) {
  pickedHour = (pickedHour + delta + 24) % 24;
  // Ограничиваем разумным диапазоном
  if (pickedHour < 0)  pickedHour = 23;
  if (pickedHour > 23) pickedHour = 0;
  document.getElementById('spin-hour').textContent = String(pickedHour).padStart(2, '0');
}

function spinMin(delta) {
  const steps = [0, 15, 30, 45];
  const idx   = steps.indexOf(pickedMinute);
  const next  = (idx + delta + steps.length) % steps.length;
  pickedMinute = steps[next];
  document.getElementById('spin-min').textContent = String(pickedMinute).padStart(2, '0');
}

function getScheduledAt() {
  if (whenMode === 'now') return null;

  const d = new Date();
  d.setDate(d.getDate() + dateOffset);
  d.setHours(pickedHour, pickedMinute, 0, 0);

  return d.toISOString();
}

// ══════════════════════════════════════════════════════════════
// СПОСОБ ОПЛАТЫ
// ══════════════════════════════════════════════════════════════
let paymentMethod = 'cash';

function setPayment(method) {
  paymentMethod = method;
  document.getElementById('payment-method').value = method;
  document.getElementById('pay-cash').classList.toggle('active',     method === 'cash');
  document.getElementById('pay-transfer').classList.toggle('active', method === 'transfer');
}

// ══════════════════════════════════════════════════════════════
// ОТПРАВКА ЗАКАЗА
// ══════════════════════════════════════════════════════════════
async function submitOrder() {
  const phone   = document.getElementById('phone').value.trim();
  const comment = document.getElementById('order-comment').value.trim();

  // Адрес: берём из точки на карте или из текста в поле
  const fromAddress = pointA
    ? pointA.address
    : document.getElementById('search-from').value.trim();
  const toAddress   = pointB
    ? pointB.address
    : document.getElementById('search-to').value.trim();

  if (!phone) {
    showFormMsg('error', 'Введите номер телефона');
    return;
  }
  if (!fromAddress) {
    showFormMsg('error', 'Укажите откуда ехать — нажмите чип, введите текст или кликните на карте');
    return;
  }
  if (!toAddress) {
    showFormMsg('error', 'Укажите куда ехать — нажмите чип, введите текст или кликните на карте');
    return;
  }

  const btn = document.getElementById('submit-btn');
  btn.disabled  = true;
  btn.innerHTML = '<span class="mini-spinner"></span> Отправляем…';

  try {
    const res = await fetch('/order', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone,
        from_address: fromAddress,
        from_lat:     pointA ? pointA.lat : null,
        from_lon:     pointA ? pointA.lng : null,
        to_address:   toAddress,
        to_lat:       pointB ? pointB.lat : null,
        to_lon:       pointB ? pointB.lng : null,
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
  } catch (e) {
    showFormMsg('error', 'Ошибка сети — проверьте соединение и попробуйте снова');
  } finally {
    btn.disabled  = false;
    btn.innerHTML = 'Заказать поездку <span class="btn-arrow">→</span>';
  }
}

function showFormMsg(type, text) {
  const el = document.getElementById('form-message');
  if (!el) return;
  el.textContent   = text;
  el.className     = `form-msg ${type}`;
  el.style.display = 'block';
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.style.display = 'none'; }, type === 'success' ? 9000 : 6000);
}

// ══════════════════════════════════════════════════════════════
// ПОДСКАЗКА "АДРЕС ПРИБЛИЗИТЕЛЬНЫЙ"
// ══════════════════════════════════════════════════════════════
// Если в адресе нет признаков улицы — показываем подсказку добавить комментарий
function checkAddressVagueness(address) {
  const hasStreet = /\b(ул|улица|пер|переулок|пр|проспект|шоссе|тракт|набережная|д\.|дом)\b/i.test(address);
  if (!hasStreet) {
    showCommentHint();
  } else {
    hideCommentHint();
  }
}

function showCommentHint() {
  const el = document.getElementById('comment-hint');
  if (el) el.style.display = 'flex';
}

function hideCommentHint() {
  const el = document.getElementById('comment-hint');
  if (el) el.style.display = 'none';
}

// ══════════════════════════════════════════════════════════════
// ФОРМА ОТЗЫВА
// ══════════════════════════════════════════════════════════════
async function submitReview() {
  const name = document.getElementById('review-name').value.trim();
  const text = document.getElementById('review-text').value.trim();

  if (!name) { showReviewMsg('error', 'Введите имя'); return; }
  if (!text || text.length < 5) { showReviewMsg('error', 'Напишите отзыв (минимум 5 символов)'); return; }

  try {
    const res  = await fetch('/review', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, text }),
    });
    const data = await res.json();

    if (data.success) {
      showReviewMsg('success', '✅ Спасибо! Отзыв отправлен на проверку.');
      document.getElementById('review-name').value = '';
      document.getElementById('review-text').value = '';
    } else {
      showReviewMsg('error', data.error || 'Ошибка');
    }
  } catch { showReviewMsg('error', 'Ошибка сети'); }
}

function showReviewMsg(type, text) {
  const el = document.getElementById('review-message');
  if (!el) return;
  el.textContent   = text;
  el.className     = `form-msg ${type}`;
  el.style.display = 'block';
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.style.display = 'none'; }, 6000);
}

// ══════════════════════════════════════════════════════════════
// УТИЛИТЫ
// ══════════════════════════════════════════════════════════════
function emptyGeoJSON() { return { type: 'FeatureCollection', features: [] }; }
function setInputVal(id, val) { const el = document.getElementById(id); if (el) el.value = val; }
function show(id) { const el = document.getElementById(id); if (el) el.style.display = ''; }
function hide(id) { const el = document.getElementById(id); if (el) el.style.display = 'none'; }
