/* ══════════════════════════════════════════════════════════
   TAXI MAP — Казанский район, Тюменская область
   MapLibre GL JS + Geoapify
══════════════════════════════════════════════════════════ */

// ── Constants ──────────────────────────────────────────────────────────────
const GEOAPIFY_KEY = window.GEOAPIFY_KEY;

// Kazansky district centre (lon, lat) — for map centre & proximity bias
const DISTRICT_LON = 69.23;
const DISTRICT_LAT = 55.73;

// Geoapify search filter: rect:lon_min,lat_min,lon_max,lat_max
// Covers Tyumen Oblast proper (excludes Tatarstan/Kazan)
const SEARCH_FILTER = 'rect:60.0,55.0,79.0,62.5';
// Proximity bias for geocoding
const SEARCH_BIAS   = `proximity:${DISTRICT_LON},${DISTRICT_LAT}`;

const ROUTE_SOURCE  = 'taxi-route';
const ROUTE_OUTLINE = 'route-outline';
const ROUTE_LINE    = 'route-line';

// ── State ──────────────────────────────────────────────────────────────────
let map       = null;
let markerA   = null;
let markerB   = null;
let pointA    = null;   // { lat, lng, address }
let pointB    = null;
let mode      = null;   // 'a' | 'b' | null
let mapReady  = false;

// ── Bootstrap ─────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initMap();
  initAutocomplete('search-from', 'a', 'dropdown-from');
  initAutocomplete('search-to',   'b', 'dropdown-to');
  document.getElementById('order-form').addEventListener('submit', onFormSubmit);
});

// ══════════════════════════════════════════════════════════
// MAP INIT
// ══════════════════════════════════════════════════════════
function initMap() {
  map = new maplibregl.Map({
    container: 'map-container',
    style: `https://maps.geoapify.com/v1/styles/osm-bright/style.json?apiKey=${GEOAPIFY_KEY}`,
    center: [DISTRICT_LON, DISTRICT_LAT],
    zoom: 10,
  });

  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

  map.on('load', () => {
    // Empty GeoJSON source for the route
    map.addSource(ROUTE_SOURCE, {
      type: 'geojson',
      data: emptyGeoJSON(),
    });

    // White outline under the route for visibility
    map.addLayer({
      id: ROUTE_OUTLINE,
      type: 'line',
      source: ROUTE_SOURCE,
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: { 'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.35 },
    });

    // Main route line
    map.addLayer({
      id: ROUTE_LINE,
      type: 'line',
      source: ROUTE_SOURCE,
      layout: { 'line-join': 'round', 'line-cap': 'round' },
      paint: { 'line-color': '#7c6fff', 'line-width': 4, 'line-opacity': 0.95 },
    });

    mapReady = true;
  });

  // Click handler — only fires when a mode is selected
  map.on('click', (e) => {
    if (!mode) return;
    const { lng, lat } = e.lngLat;
    handleMapClick(lat, lng);
  });

  // Change cursor when mode is active
  map.on('mousemove', () => {
    map.getCanvas().style.cursor = mode ? 'crosshair' : '';
  });
}

// ══════════════════════════════════════════════════════════
// MODE SELECTION
// ══════════════════════════════════════════════════════════
function setMode(newMode) {
  mode = newMode;

  const btnA = document.getElementById('btn-mode-a');
  const btnB = document.getElementById('btn-mode-b');
  const hint = document.getElementById('map-hint');

  btnA.classList.remove('mode-active', 'mode-active-b');
  btnB.classList.remove('mode-active', 'mode-active-b');

  if (newMode === 'a') {
    btnA.classList.add('mode-active');
    hint.textContent = 'Кликните на карте, чтобы выбрать точку ОТКУДА';
  } else if (newMode === 'b') {
    btnB.classList.add('mode-active-b');
    hint.textContent = 'Кликните на карте, чтобы выбрать точку КУДА';
  } else {
    hint.textContent = 'Выберите режим и кликайте на карту';
  }

  if (map) map.getCanvas().style.cursor = newMode ? 'crosshair' : '';
}

// ══════════════════════════════════════════════════════════
// MAP CLICK HANDLER
// ══════════════════════════════════════════════════════════
async function handleMapClick(lat, lng) {
  const currentMode = mode; // capture before async

  // Show loading in hint
  const hint = document.getElementById('map-hint');
  const prevHint = hint.textContent;
  hint.textContent = '⏳ Определяем адрес…';

  const address = await reverseGeocode(lat, lng);
  hint.textContent = prevHint;

  if (currentMode === 'a') {
    placePointA(lat, lng, address);
  } else if (currentMode === 'b') {
    placePointB(lat, lng, address);
  }

  if (pointA && pointB) {
    buildRoute();
  }
}

// ══════════════════════════════════════════════════════════
// POINT PLACEMENT
// ══════════════════════════════════════════════════════════
function placePointA(lat, lng, address) {
  if (markerA) { markerA.remove(); markerA = null; }

  pointA = { lat, lng, address };

  markerA = new maplibregl.Marker({ element: createMarkerEl('A', '#7c6fff') })
    .setLngLat([lng, lat])
    .addTo(map);

  // Sync input and hidden fields
  setInputValue('search-from', address);
  setHiddenFields('from', lat, lng, address);

  // Clear old route when point A changes
  clearRouteData();
}

function placePointB(lat, lng, address) {
  if (markerB) { markerB.remove(); markerB = null; }

  pointB = { lat, lng, address };

  markerB = new maplibregl.Marker({ element: createMarkerEl('B', '#ff6b9d') })
    .setLngLat([lng, lat])
    .addTo(map);

  setInputValue('search-to', address);
  setHiddenFields('to', lat, lng, address);

  // Clear old route when point B changes
  clearRouteData();
}

function setInputValue(id, value) {
  const el = document.getElementById(id);
  if (el) el.value = value;
}

function setHiddenFields(prefix, lat, lng, address) {
  const set = (suffix, val) => {
    const el = document.getElementById(`${prefix}-${suffix}`);
    if (el) el.value = val;
  };
  set('lat', lat);
  set('lon', lng);
  set('address', address);
}

// ══════════════════════════════════════════════════════════
// MARKER ELEMENT
// ══════════════════════════════════════════════════════════
function createMarkerEl(label, color) {
  const wrap = document.createElement('div');
  wrap.className = 'map-marker';
  wrap.style.backgroundColor = color;

  const lbl = document.createElement('div');
  lbl.className = 'map-marker-label';
  lbl.textContent = label;

  wrap.appendChild(lbl);
  return wrap;
}

// ══════════════════════════════════════════════════════════
// REVERSE GEOCODING
// ══════════════════════════════════════════════════════════
async function reverseGeocode(lat, lon) {
  try {
    const url = new URL('https://api.geoapify.com/v1/geocode/reverse');
    url.searchParams.set('lat', lat);
    url.searchParams.set('lon', lon);
    url.searchParams.set('lang', 'ru');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();

    if (data.features && data.features.length > 0) {
      return data.features[0].properties.formatted
          || `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
    }
  } catch (err) {
    console.error('[Geocode reverse]', err);
  }
  return `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
}

// ══════════════════════════════════════════════════════════
// FORWARD GEOCODING (search autocomplete)
// ══════════════════════════════════════════════════════════
async function searchAddress(query) {
  if (!query || query.trim().length < 2) return [];

  try {
    const url = new URL('https://api.geoapify.com/v1/geocode/search');
    url.searchParams.set('text',   query.trim());
    url.searchParams.set('filter', SEARCH_FILTER);
    url.searchParams.set('bias',   SEARCH_BIAS);
    url.searchParams.set('lang',   'ru');
    url.searchParams.set('limit',  '6');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();

    return data.features || [];
  } catch (err) {
    console.error('[Geocode search]', err);
    return [];
  }
}

// ══════════════════════════════════════════════════════════
// AUTOCOMPLETE WIDGET
// ══════════════════════════════════════════════════════════
function initAutocomplete(inputId, pointType, dropdownId) {
  const input    = document.getElementById(inputId);
  const dropdown = document.getElementById(dropdownId);
  if (!input || !dropdown) return;

  let debounceTimer;

  input.addEventListener('input', () => {
    clearTimeout(debounceTimer);
    const query = input.value.trim();

    if (query.length < 2) {
      hideDropdown(dropdown);
      return;
    }

    debounceTimer = setTimeout(async () => {
      const features = await searchAddress(query);
      renderDropdown(dropdown, features, (feature) => {
        const props = feature.properties;
        const addr  = props.formatted || '';
        const lat   = props.lat;
        const lon   = props.lon;

        input.value = addr;
        hideDropdown(dropdown);

        if (pointType === 'a') {
          placePointA(lat, lon, addr);
          map.flyTo({ center: [lon, lat], zoom: 13 });
        } else {
          placePointB(lat, lon, addr);
          map.flyTo({ center: [lon, lat], zoom: 13 });
        }

        if (pointA && pointB) buildRoute();
      });
    }, 300);
  });

  // Close dropdown when clicking outside
  document.addEventListener('click', (e) => {
    if (!input.contains(e.target) && !dropdown.contains(e.target)) {
      hideDropdown(dropdown);
    }
  });

  // Keyboard navigation
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') hideDropdown(dropdown);
  });
}

function renderDropdown(dropdown, features, onSelect) {
  dropdown.innerHTML = '';

  if (!features.length) {
    hideDropdown(dropdown);
    return;
  }

  features.forEach((feature) => {
    const item = document.createElement('div');
    item.className = 'autocomplete-item';
    item.textContent = feature.properties.formatted || '';
    item.addEventListener('mousedown', (e) => {
      e.preventDefault(); // prevent input blur before click
      onSelect(feature);
    });
    dropdown.appendChild(item);
  });

  dropdown.style.display = 'block';
}

function hideDropdown(dropdown) {
  dropdown.style.display = 'none';
  dropdown.innerHTML = '';
}

// ══════════════════════════════════════════════════════════
// ROUTING
// ══════════════════════════════════════════════════════════
async function buildRoute() {
  if (!pointA || !pointB) return;
  if (!mapReady)          return;

  showRouteLoading(true);

  try {
    const url = new URL('https://api.geoapify.com/v1/routing');
    // NOTE: Geoapify routing uses lat,lon order (not GeoJSON lon,lat)
    url.searchParams.set('waypoints', `${pointA.lat},${pointA.lng}|${pointB.lat},${pointB.lng}`);
    url.searchParams.set('mode',   'drive');
    url.searchParams.set('apiKey', GEOAPIFY_KEY);

    const res  = await fetch(url.toString());
    const data = await res.json();

    if (data.features && data.features.length > 0) {
      // Set route on map source
      map.getSource(ROUTE_SOURCE).setData(data);

      // Show route info
      const props  = data.features[0].properties;
      const distKm = (props.distance / 1000).toFixed(1);
      const mins   = Math.round(props.time / 60);
      showRouteInfo(`Маршрут: ${distKm} км · ~${mins} мин`);

      // Fit map to show full route
      fitBounds(data.features[0].geometry);
    } else {
      showRouteInfo('Маршрут не найден. Проверьте точки.');
    }
  } catch (err) {
    console.error('[Routing]', err);
    showRouteInfo('Ошибка построения маршрута');
  } finally {
    showRouteLoading(false);
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
  map.fitBounds(bounds, { padding: 70, maxZoom: 14, duration: 800 });
}

function clearRouteData() {
  if (mapReady && map.getSource(ROUTE_SOURCE)) {
    map.getSource(ROUTE_SOURCE).setData(emptyGeoJSON());
  }
  hideRouteInfo();
}

// ══════════════════════════════════════════════════════════
// RESET
// ══════════════════════════════════════════════════════════
function resetAll() {
  // Remove markers
  if (markerA) { markerA.remove(); markerA = null; }
  if (markerB) { markerB.remove(); markerB = null; }
  pointA = null;
  pointB = null;

  // Clear route
  clearRouteData();

  // Clear all form / input fields
  ['search-from', 'search-to'].forEach((id) => setInputValue(id, ''));
  ['from-lat', 'from-lon', 'from-address',
   'to-lat',   'to-lon',   'to-address'].forEach((id) => setInputValue(id, ''));

  // Close dropdowns
  document.querySelectorAll('.autocomplete-dropdown').forEach(hideDropdown);

  // Reset mode
  setMode(null);

  // Fly back to district centre
  map.flyTo({ center: [DISTRICT_LON, DISTRICT_LAT], zoom: 10, duration: 600 });
}

// ══════════════════════════════════════════════════════════
// UI HELPERS
// ══════════════════════════════════════════════════════════
function showRouteLoading(visible) {
  const el = document.getElementById('route-loading');
  if (el) el.style.display = visible ? 'flex' : 'none';
}

function showRouteInfo(text) {
  const el = document.getElementById('route-info');
  if (!el) return;
  el.textContent = text;
  el.style.display = 'flex';
}

function hideRouteInfo() {
  const el = document.getElementById('route-info');
  if (el) el.style.display = 'none';
}

function emptyGeoJSON() {
  return { type: 'FeatureCollection', features: [] };
}

// ══════════════════════════════════════════════════════════
// ORDER FORM SUBMIT
// ══════════════════════════════════════════════════════════
async function onFormSubmit(e) {
  e.preventDefault();

  const phone       = document.getElementById('phone').value.trim();
  const fromAddress = document.getElementById('from-address').value;
  const fromLat     = document.getElementById('from-lat').value;
  const fromLon     = document.getElementById('from-lon').value;
  const toAddress   = document.getElementById('to-address').value;
  const toLat       = document.getElementById('to-lat').value;
  const toLon       = document.getElementById('to-lon').value;
  const scheduledAt = document.getElementById('scheduled-at').value;

  if (!phone) {
    showMsg('error', 'Введите номер телефона');
    return;
  }
  if (!fromLat || !fromLon) {
    showMsg('error', 'Выберите точку ОТКУДА на карте или в поиске');
    return;
  }
  if (!toLat || !toLon) {
    showMsg('error', 'Выберите точку КУДА на карте или в поиске');
    return;
  }

  const btn = document.getElementById('submit-btn');
  btn.disabled    = true;
  btn.textContent = 'Отправляем…';

  try {
    const res = await fetch('/order', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        phone,
        from_address: fromAddress,
        from_lat:     parseFloat(fromLat),
        from_lon:     parseFloat(fromLon),
        to_address:   toAddress,
        to_lat:       parseFloat(toLat),
        to_lon:       parseFloat(toLon),
        scheduled_at: scheduledAt || null,
      }),
    });

    const data = await res.json();

    if (data.success) {
      showMsg('success', `✅ Заказ #${data.order_id} принят! Ожидайте звонка диспетчера.`);
      resetAll();
      document.getElementById('scheduled-at').value = '';
      document.getElementById('phone').value = '';
    } else {
      showMsg('error', data.error || 'Ошибка при создании заказа');
    }
  } catch (err) {
    console.error('[Order submit]', err);
    showMsg('error', 'Ошибка сети. Попробуйте ещё раз.');
  } finally {
    btn.disabled    = false;
    btn.textContent = 'Заказать поездку';
  }
}

function showMsg(type, text) {
  const el = document.getElementById('form-message');
  if (!el) return;
  el.textContent = text;
  el.className   = `form-message ${type}`;
  el.style.display = 'block';

  // Auto-hide after a delay
  clearTimeout(el._timer);
  el._timer = setTimeout(() => { el.style.display = 'none'; }, type === 'success' ? 9000 : 6000);
}

// ══════════════════════════════════════════════════════════
// REVIEW FORM
// ══════════════════════════════════════════════════════════
async function submitReview() {
  const name = document.getElementById('review-name').value.trim();
  const text = document.getElementById('review-text').value.trim();
  const msg  = document.getElementById('review-message');

  if (!name) { showReviewMsg('error', 'Введите ваше имя'); return; }
  if (!text) { showReviewMsg('error', 'Напишите текст отзыва'); return; }
  if (text.length < 10) { showReviewMsg('error', 'Отзыв слишком короткий'); return; }

  try {
    const res = await fetch('/review', {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, text }),
    });
    const data = await res.json();

    if (data.success) {
      showReviewMsg('success', '✅ Спасибо! Отзыв отправлен на проверку.');
      document.getElementById('review-name').value = '';
      document.getElementById('review-text').value = '';
    } else {
      showReviewMsg('error', data.error || 'Ошибка при отправке');
    }
  } catch (err) {
    showReviewMsg('error', 'Ошибка сети. Попробуйте позже.');
  }
}

function showReviewMsg(type, text) {
  const el = document.getElementById('review-message');
  if (!el) return;
  el.textContent   = text;
  el.className     = `form-message ${type}`;
  el.style.display = 'block';
  clearTimeout(el._timer);
  el._timer = setTimeout(() => { el.style.display = 'none'; }, 6000);
}
