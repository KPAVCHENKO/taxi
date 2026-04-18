/* ══════════════════════════════════════════════════════
   TAXI MAP · Казанский район — Yandex Maps 2.1
══════════════════════════════════════════════════════ */

// Ограничивающий прямоугольник: Казанский район + Ишим + Петропавловск
const BOUNDS = [[54.3, 65.5], [57.5, 72.5]];
const CENTER = [55.73, 69.23]; // Центр Казанского района

// Популярные населённые пункты
const PLACES = [
  { name: 'Казанское',        q: 'Казанское, Казанский район, Тюменская область' },
  { name: 'Ишим',             q: 'Ишим, Тюменская область' },
  { name: 'Новоселезнево',    q: 'Новоселезнево, Казанский район, Тюменская область' },
  { name: 'Большие Ярки',     q: 'Большие Ярки, Казанский район, Тюменская область' },
  { name: 'Ильинка',          q: 'Ильинка, Казанский район, Тюменская область' },
  { name: 'Яровское',         q: 'Яровское, Казанский район, Тюменская область' },
  { name: 'Петропавловск',    q: 'Петропавловск, Северо-Казахстанская область, Казахстан' },
];

// ── Таблица цен (из Казанского) ────────────────────────
const PRICE_TABLE = {
  'казанское':         150,
  'новоселезнево':     200,
  'шадринка':          300,
  'яровское':          300,
  'большие ярки':      300,
  'малые ярки':        400,
  'гагарье':           500,
  'сладчанка':         500,
  'боровлянка':        600,
  'дальнетравное':     600,
  'ильинка':           700,
  'кугаево':           700,
  'чирки':             700,
  'огнево':            800,
  'дубынка':           900,
  'заречка':           900,
  'смирное':           900,
  'афонькино':         1000,
  'пешнево':           1000,
  'копотилово':        1000,
  'ченчерь':           1000,
  'ельцово':           1000,
  'коротаевка':        1100,
  'грачи':             1200,
  'паленка':           1200,
  'новогеоргиевка':    1500,
  'новоалександровка': 1500,
  'челюскинцев':       1500,
  'викторовка':        1800,
  'долматово':         1800,
};

const PRICE_INTERCITY = {
  'ишим':          { one_way: 2000, round_trip: 3000 },
  'петропавловск': { one_way: 5000, round_trip: 7500 },
};

// ── Состояние ──────────────────────────────────────────
let ymap       = null;
let placemarkA = null, placemarkB = null;
let pointA     = null, pointB = null; // { lat, lon, address }
let mode       = 'a';
let routeObj   = null;

let whenMode      = 'now';
let dateOffset    = 0;       // 0=сегодня, 1=завтра, 2=послезавтра
let customDate    = null;    // 'YYYY-MM-DD' если выбрано через календарь
let dateMode      = 'quick'; // 'quick' | 'custom'
let pickedHour    = 12;
let pickedMinute  = 0;
let paymentMethod = 'cash';

// ══════════════════════════════════════════════════════
// ИНИЦИАЛИЗАЦИЯ
// ══════════════════════════════════════════════════════
ymaps.ready(function () {
  if (!window.NO_MAP) initMap();
  initAddressInputs();
  renderChips();
  renderDateChips();
  renderTimePresets();
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
  if (ymap && placemarkA) ymap.geoObjects.remove(placemarkA);
  pointA = { lat, lon, address };

  if (ymap) {
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
  }
  setInputVal('search-from', address);
  show('clear-a');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
  updatePriceDisplay();
}

function placePointB(lat, lon, address) {
  if (ymap && placemarkB) ymap.geoObjects.remove(placemarkB);
  pointB = { lat, lon, address };

  if (ymap) {
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
  }
  setInputVal('search-to', address);
  show('clear-b');
  clearRouteData();
  updateChipStates();
  checkAddressVagueness(address);
  updatePriceDisplay();
}

function clearPoint(which) {
  if (which === 'a') {
    if (ymap && placemarkA) ymap.geoObjects.remove(placemarkA);
    placemarkA = null;
    pointA = null;
    setInputVal('search-from', '');
    hide('clear-a');
    setMode('a');
  } else {
    if (ymap && placemarkB) ymap.geoObjects.remove(placemarkB);
    placemarkB = null;
    pointB = null;
    setInputVal('search-to', '');
    hide('clear-b');
  }
  clearRouteData();
  updateChipStates();
  updatePriceDisplay();
}

function swapPoints() {
  const tmpA = pointA ? { ...pointA } : null;
  const tmpB = pointB ? { ...pointB } : null;
  if (ymap && placemarkA) ymap.geoObjects.remove(placemarkA);
  if (ymap && placemarkB) ymap.geoObjects.remove(placemarkB);
  placemarkA = null; placemarkB = null;
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
  if (!ymap) return;
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
  if (ymap && routeObj) { ymap.geoObjects.remove(routeObj); routeObj = null; }
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

// ── Строим поисковый запрос со смарт-контекстом ──────────
// Если уже известна другая точка — добавляем её город как контекст,
// чтобы "улица Ленина" нашла нужный город, а не любой.
function buildSearchQuery(query) {
  const lower = query.toLowerCase();

  // Пользователь явно написал город — не добавляем
  if (/петропавловск|ишим|тюмень|омск|новосибирск/.test(lower)) return query;
  if (/казанск|тюменск/.test(lower)) return query;

  // Смотрим на другую уже установленную точку
  const otherAddr = (mode === 'b' && pointA) ? (pointA.address  || '').toLowerCase()
                  : (mode === 'a' && pointB) ? (pointB.address  || '').toLowerCase()
                  : '';

  if (otherAddr.includes('ишим'))          return query + ', Ишим, Тюменская область';
  if (otherAddr.includes('петропавловск')) return query + ', Петропавловск, Казахстан';

  // По умолчанию — Казанский район
  return query + ', Казанский район, Тюменская область';
}

// ── Основной поиск через ymaps.geocode ──────────────────
// ymaps.geocode доступен без дополнительных модулей и находит:
// адреса улиц/домов И организации (Магнит, аптека и т.д.),
// если они есть в базе Яндекс Карт.
async function getSuggestions(query) {
  const local = getLocalMatches(query);

  try {
    const res = await ymaps.geocode(buildSearchQuery(query), {
      boundedBy:    BOUNDS,
      strictBounds: false,
      results:      6,
    });

    const items = [];
    res.geoObjects.each(function (obj) {
      const coords = obj.geometry ? obj.geometry.getCoordinates() : null;
      if (!coords) return;

      const name  = obj.properties.get('name')        || '';
      const desc  = obj.properties.get('description') || '';
      const addr  = obj.getAddressLine()              || '';

      // Это организация/POI если у объекта есть отдельное имя
      const isPOI = name && name !== addr && name.length < 80;

      // Полный лейбл — то что попадёт в поле и в заказ водителю
      const label = isPOI ? (name + (addr ? ', ' + addr : '')) : addr;

      // Не дублируем локальные чипы
      if (local.some(l => label.toLowerCase().includes(l._localName.toLowerCase()))) return;

      items.push({
        displayName: isPOI ? name : addr,
        subDisplay:  isPOI ? addr : (desc || null),
        _fullLabel:  label,
        _geoCoords:  coords,
        _isPOI:      isPOI,
      });
    });

    return [...local, ...items];
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

        if (item._geoCoords) {
          // search/geocode-результат — координаты уже есть
          lat  = item._geoCoords[0];
          lon  = item._geoCoords[1];
          addr = item._fullLabel || item.displayName;
        } else if (item._isLocal) {
          const r = await geocodeQuery(item._localQuery);
          if (!r) { showFormMsg('error', `Не удалось найти «${item._localName}»`); return; }
          lat = r.lat; lon = r.lon;
          addr = item._localName;
        } else {
          const r = await geocodeQuery(item.value || item.displayName);
          if (!r) { showFormMsg('error', 'Не удалось определить координаты адреса'); return; }
          lat = r.lat; lon = r.lon;
          addr = r.address || item.displayName;
        }

        if (pointType === 'a') {
          placePointA(lat, lon, addr);
          if (ymap) ymap.setCenter([lat, lon], 13);
          if (!pointB) setMode('b');
        } else {
          placePointB(lat, lon, addr);
          if (ymap) ymap.setCenter([lat, lon], 13);
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
    drop.innerHTML =
      '<div class="drop-no-result">' +
        'Не найдено<br>' +
        '<span style="font-size:11px;opacity:.7;">Добавьте название села: <em>Яровское, Новая 11</em><br>Или кликните прямо на карте</span>' +
      '</div>';
    drop.style.display = 'block';
    return;
  }

  items.forEach(item => {
    const div = document.createElement('div');

    let icon, main, sub, cls;

    if (item._isLocal) {
      cls  = 'drop-item drop-item-local';
      icon = '🏘';
      main = item._localName;
      sub  = 'Казанский район';
    } else if (item._isPOI) {
      cls  = 'drop-item drop-item-poi';
      icon = '🏪';
      main = item.displayName;
      sub  = item.subDisplay || '';
    } else {
      cls  = 'drop-item';
      icon = '📍';
      main = item.displayName;
      sub  = item.subDisplay || '';
    }

    div.className = cls;
    div.innerHTML =
      `<span class="drop-icon">${icon}</span>` +
      `<span class="drop-text">` +
        `<strong>${escHtml(main)}</strong>` +
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

  if (ymap) ymap.setCenter([r.lat, r.lon], 12);
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
  if (w === 'later') {
    // прокрутить пресеты до текущего часа
    const active = document.querySelector('.dp-time-btn.dp-time-active');
    if (active) setTimeout(() => active.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' }), 120);
  }
}

// ── Дата ────────────────────────────────────────────────
function renderDateChips() {
  // Устанавливаем min у скрытого input (сегодня)
  const inp = document.getElementById('dp-date-input');
  if (inp) {
    const today = new Date();
    inp.min = today.toISOString().slice(0, 10);
  }
}

function pickDateQuick(offset) {
  dateOffset = offset;
  dateMode   = 'quick';
  customDate = null;

  // сбросить подсветку всех быстрых кнопок
  [0, 1, 2].forEach(i => {
    const el = document.getElementById('dpq-' + i);
    if (el) el.classList.toggle('dp-chip-active', i === offset);
  });
  const cal = document.getElementById('dpq-custom');
  if (cal) {
    cal.classList.remove('dp-chip-active');
    document.getElementById('dp-custom-label').textContent = 'Другая дата';
  }
}

function openCalendar() {
  const inp = document.getElementById('dp-date-input');
  if (!inp) return;
  inp.click();
}

function onCalendarChange(val) {
  if (!val) return;
  customDate = val;
  dateMode   = 'custom';

  // снять выделение с быстрых кнопок
  [0, 1, 2].forEach(i => {
    const el = document.getElementById('dpq-' + i);
    if (el) el.classList.remove('dp-chip-active');
  });

  // показать выбранную дату на кнопке календаря
  const d = new Date(val + 'T00:00:00');
  const months = ['янв','фев','мар','апр','май','июн','июл','авг','сен','окт','ноя','дек'];
  const weekdays = ['вс','пн','вт','ср','чт','пт','сб'];
  const label = weekdays[d.getDay()] + ', ' + d.getDate() + ' ' + months[d.getMonth()];
  document.getElementById('dp-custom-label').textContent = label;
  const cal = document.getElementById('dpq-custom');
  if (cal) cal.classList.add('dp-chip-active');
}

// ── Время ────────────────────────────────────────────────
const TIME_PRESETS = [6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23];

function renderTimePresets() {
  const container = document.getElementById('dp-time-presets');
  if (!container) return;
  container.innerHTML = '';
  TIME_PRESETS.forEach(h => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'dp-time-btn' + (h === pickedHour && pickedMinute === 0 ? ' dp-time-active' : '');
    btn.textContent = String(h).padStart(2, '0') + ':00';
    btn.onclick = () => {
      pickedHour = h;
      pickedMinute = 0;
      updateTimeDisplay();
      document.querySelectorAll('.dp-time-btn').forEach(b => b.classList.remove('dp-time-active'));
      btn.classList.add('dp-time-active');
      btn.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    };
    container.appendChild(btn);
  });
}

function updateTimeDisplay() {
  const h = document.getElementById('spin-hour');
  const m = document.getElementById('spin-min');
  if (h) h.textContent = String(pickedHour).padStart(2, '0');
  if (m) m.textContent = String(pickedMinute).padStart(2, '0');
}

function spinHour(delta) {
  pickedHour = (pickedHour + delta + 24) % 24;
  updateTimeDisplay();
  // снять выделение с пресетов, подсветить если есть совпадение
  document.querySelectorAll('.dp-time-btn').forEach(b => {
    b.classList.toggle('dp-time-active',
      b.textContent === String(pickedHour).padStart(2,'0') + ':00' && pickedMinute === 0);
  });
}

function spinMin(delta) {
  const steps = [0, 15, 30, 45];
  const idx = steps.indexOf(pickedMinute);
  pickedMinute = steps[(idx + delta + steps.length) % steps.length];
  updateTimeDisplay();
  // если минуты ≠ 0, снять выделение с пресетов
  if (pickedMinute !== 0) {
    document.querySelectorAll('.dp-time-btn').forEach(b => b.classList.remove('dp-time-active'));
  }
}

function getScheduledAt() {
  if (whenMode === 'now') return null;
  let d;
  if (dateMode === 'custom' && customDate) {
    d = new Date(customDate + 'T00:00:00');
  } else {
    d = new Date();
    d.setDate(d.getDate() + dateOffset);
  }
  d.setHours(pickedHour, pickedMinute, 0, 0);
  return d.toISOString();
}

// ══════════════════════════════════════════════════════
// АВТОЦЕНА
// ══════════════════════════════════════════════════════
function matchSettlement(addr) {
  if (!addr) return null;
  const a = addr.toLowerCase();
  for (const name of Object.keys(PRICE_INTERCITY)) {
    if (a.includes(name)) return { name, type: 'intercity' };
  }
  for (const name of Object.keys(PRICE_TABLE)) {
    if (a.includes(name)) return { name, type: 'local' };
  }
  return null;
}

function lookupPrice() {
  if (!pointA || !pointB) return null;
  const mA = matchSettlement(pointA.address);
  const mB = matchSettlement(pointB.address);
  if (!mA || !mB) return null;

  // Один из пунктов должен быть Казанское
  let dest = null;
  if (mA.name === 'казанское') dest = mB;
  else if (mB.name === 'казанское') dest = mA;
  else return null; // маршрут не из Казанского — не авторасчёт

  if (dest.type === 'intercity') {
    return { ...PRICE_INTERCITY[dest.name], type: 'intercity' };
  }
  return { price: PRICE_TABLE[dest.name], type: 'local' };
}

function updatePriceDisplay() {
  const el = document.querySelector('.price-text');
  if (!el) return;

  const p = lookupPrice();
  const hiddenInput = document.getElementById('estimated-price');

  if (!p) {
    el.innerHTML = '💰 Цена уточняется диспетчером';
    if (hiddenInput) hiddenInput.value = '';
    return;
  }

  let priceVal, html;
  if (p.type === 'intercity') {
    priceVal = p.one_way;
    const ow = p.one_way.toLocaleString('ru-RU');
    const rt = p.round_trip.toLocaleString('ru-RU');
    html = `💰 <strong class="price-amount">${ow} ₽</strong>`
         + `<span class="price-detail"> · туда-обратно ${rt} ₽</span>`;
  } else {
    priceVal = p.price;
    html = `💰 <strong class="price-amount">${p.price.toLocaleString('ru-RU')} ₽</strong>`;
  }

  if (rideType === 'shared') {
    html += '<span class="price-shared-note"> попутно — дешевле</span>';
  }

  el.innerHTML = html;
  if (hiddenInput) hiddenInput.value = priceVal;
}

// ══════════════════════════════════════════════════════
// ТИП ПОЕЗДКИ
// ══════════════════════════════════════════════════════
let rideType = 'individual';

function setRideType(type) {
  rideType = type;
  document.getElementById('ride-type').value = type;
  document.getElementById('rt-individual').classList.toggle('rt-active', type === 'individual');
  document.getElementById('rt-shared').classList.toggle('rt-active', type === 'shared');
  updatePriceDisplay();
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

  const consentEl = document.getElementById('consent-checkbox');
  if (consentEl && !consentEl.checked) {
    showFormMsg('error', 'Необходимо согласиться с обработкой персональных данных');
    consentEl.closest('.consent-section').scrollIntoView({ behavior: 'smooth', block: 'center' });
    return;
  }
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
        comment:         comment || null,
        payment:         paymentMethod,
        ride_type:       rideType,
        estimated_price: document.getElementById('estimated-price').value || null,
        scheduled_at:    getScheduledAt(),
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
      setRideType('individual');
      pickDateQuick(0);
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
