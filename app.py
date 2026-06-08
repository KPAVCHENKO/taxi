import os
import time
import json as _json_mod
from datetime import datetime, timedelta
from functools import wraps

from flask import (
    Flask, render_template, request, jsonify,
    session, redirect, url_for, flash, make_response, Response, send_file,
)
from flask_migrate import Migrate
from sqlalchemy import text
from models import db, Order, Driver, Review, Tariff, DispatchLog, DriverApplication, PushSubscription, DriverPushSubscription, ChatMessage
import telegram_bot

app = Flask(__name__)

# ── APScheduler (плановые напоминания) ────────────────────────────────────────
try:
    from apscheduler.schedulers.background import BackgroundScheduler
    _scheduler = BackgroundScheduler(daemon=True)

    def _check_reminders():
        with app.app_context():
            now  = datetime.utcnow()
            win_start = now + timedelta(minutes=60)
            win_end   = now + timedelta(minutes=120)
            orders = Order.query.filter(
                Order.status == 'accepted',
                Order.scheduled_at.isnot(None),
                Order.reminder_sent == False,
                Order.scheduled_at >= win_start,
                Order.scheduled_at <= win_end,
            ).all()
            for o in orders:
                try:
                    if o.driver_telegram_id and not o.driver_telegram_id.startswith('max:'):
                        telegram_bot.send_scheduled_reminder(o)
                    o.reminder_sent = True
                    db.session.commit()
                except Exception as _re:
                    print(f'[reminder] error order {o.id}: {_re}')
                    db.session.rollback()

    def _renotify_new_orders():
        """Повторно пушим непринятые заказы — чтобы водитель точно увидел (как в настоящих приложениях)."""
        with app.app_context():
            now = datetime.utcnow()
            lo  = now - timedelta(minutes=15)
            hi  = now - timedelta(minutes=2)
            orders = Order.query.filter(
                Order.status == 'new',
                Order.created_at >= lo,
                Order.created_at <= hi,
            ).all()
            for o in orders:
                try:
                    _send_push_to_driver_subs('🚖 Заказ ждёт водителя!',
                                              f'{o.from_address} → {o.to_address}', '/driver/')
                    _send_push_to_all('⏳ Заказ ещё не принят',
                                      f'#{o.id}: {o.from_address} → {o.to_address}', '/admin/dispatcher')
                except Exception as _re:
                    print(f'[renotify] error order {o.id}: {_re}')

    _scheduler.add_job(_check_reminders, 'interval', minutes=10, id='reminders')
    _scheduler.add_job(_renotify_new_orders, 'interval', minutes=3, id='renotify')
    _scheduler.start()
except Exception as _sched_err:
    print(f'[APScheduler] not started: {_sched_err}')

STATIC_VER = os.environ.get('RAILWAY_DEPLOYMENT_ID', str(int(time.time())))

@app.context_processor
def inject_static_ver():
    return dict(static_ver=STATIC_VER, now=datetime.utcnow,
                site_url=SITE_URL, geo_lat=GEO_LAT, geo_lon=GEO_LON)

@app.after_request
def set_cache_headers(response):
    if request.path.startswith('/static/'):
        response.headers['Cache-Control'] = 'public, max-age=31536000, immutable'
    elif request.endpoint in ('index', 'privacy', 'offer', 'admin_login'):
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
    return response


# ── Yandex.Metrika (счётчик на все HTML-страницы) ─────────────────────────────
METRIKA_HTML = """<!-- Yandex.Metrika counter --> <script type="text/javascript">     (function(m,e,t,r,i,k,a){         m[i]=m[i]||function(){(m[i].a=m[i].a||[]).push(arguments)};         m[i].l=1*new Date();         for (var j = 0; j < document.scripts.length; j++) {if (document.scripts[j].src === r) { return; }}         k=e.createElement(t),a=e.getElementsByTagName(t)[0],k.async=1,k.src=r,a.parentNode.insertBefore(k,a)     })(window, document,'script','https://mc.webvisor.org/metrika/tag_ww.js?id=109627527', 'ym');      ym(109627527, 'init', {ssr:true, webvisor:true, trackHash:true, clickmap:true, ecommerce:"dataLayer", referrer: document.referrer, url: location.href, accurateTrackBounce:true, trackLinks:true}); </script>  <!-- /Yandex.Metrika counter -->"""

@app.after_request
def inject_metrika(response):
    try:
        if (not response.direct_passthrough
                and 'text/html' in (response.content_type or '')):
            body = response.get_data(as_text=True)
            if '<head' in body and 'tag_ww.js?id=109627527' not in body:
                import re as _re
                body = _re.sub(r'<head[^>]*>',
                               lambda m: m.group(0) + '\n' + METRIKA_HTML,
                               body, count=1)
                response.set_data(body)
    except Exception:
        pass
    return response

# ── Config ────────────────────────────────────────────────────────────────────
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'change-me-in-production-please')
app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(days=365)

_db_url = os.environ.get('DATABASE_URL', 'sqlite:///taxi.db')
if _db_url.startswith('postgres://'):
    _db_url = _db_url.replace('postgres://', 'postgresql+pg8000://', 1)
elif _db_url.startswith('postgresql://'):
    _db_url = _db_url.replace('postgresql://', 'postgresql+pg8000://', 1)
elif _db_url.startswith('postgresql+psycopg2://'):
    _db_url = _db_url.replace('postgresql+psycopg2://', 'postgresql+pg8000://', 1)

app.config['SQLALCHEMY_DATABASE_URI'] = _db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

ADMIN_PASSWORD   = os.environ.get('ADMIN_PASSWORD', 'admin123')
YANDEX_MAPS_KEY  = os.environ.get('YANDEX_MAPS_KEY', '')
COMMISSION_RATE       = float(os.environ.get('COMMISSION_RATE', '20')) / 100
INTERCITY_COMMISSION  = int(os.environ.get('INTERCITY_COMMISSION', '200'))  # фикс. комиссия с межгорода ₽
MAX_BOT_TOKEN    = os.environ.get('MAX_BOT_TOKEN', '')

def _normalize_vapid_key(k):
    """Чинит VAPID private key, если в переменной окружения потерялись переводы строк
    (частая проблема при вставке многострочного PEM в панель Railway)."""
    if not k:
        return k
    import re as _re
    k = k.strip().replace('\\n', '\n')
    if '-----BEGIN' in k:
        m = _re.match(r'^-----BEGIN ([A-Z0-9 ]+?)-----\s*(.*?)\s*-----END \1-----\s*$', k, _re.S)
        if m:
            label   = m.group(1).strip()
            body    = _re.sub(r'\s+', '', m.group(2))
            wrapped = '\n'.join(body[i:i+64] for i in range(0, len(body), 64))
            k = f'-----BEGIN {label}-----\n{wrapped}\n-----END {label}-----\n'
    return k

VAPID_PRIVATE_KEY = _normalize_vapid_key(os.environ.get('VAPID_PRIVATE_KEY', ''))
VAPID_PUBLIC_KEY  = os.environ.get('VAPID_PUBLIC_KEY', '')
VAPID_EMAIL       = os.environ.get('VAPID_EMAIL', 'mailto:admin@example.com')

OWNER_NAME      = os.environ.get('OWNER_NAME',    'ИП Иванов Иван Иванович')
OWNER_OGRN      = os.environ.get('OWNER_OGRN',    '000000000000000')
OWNER_INN       = os.environ.get('OWNER_INN',     '000000000000')
OWNER_ADDRESS   = os.environ.get('OWNER_ADDRESS', 'Тюменская область, Казанский район, с. Казанское')
OWNER_PHONE     = os.environ.get('OWNER_PHONE',   '+7 (963) 060-84-19')
OWNER_PHONE_RAW = os.environ.get('OWNER_PHONE_RAW', '+79630608419')
OWNER_EMAIL     = os.environ.get('OWNER_EMAIL',   'info@example.ru')
SITE_URL        = os.environ.get('SITE_URL',      'https://kazanskoe-taxi.xyz').rstrip('/')

# Координаты с. Казанское (Тюменская область) — для гео-разметки SEO
GEO_LAT = os.environ.get('GEO_LAT', '55.6456')
GEO_LON = os.environ.get('GEO_LON', '69.2206')

def legal_ctx():
    return dict(
        owner_name=OWNER_NAME, owner_ogrn=OWNER_OGRN, owner_inn=OWNER_INN,
        owner_address=OWNER_ADDRESS, owner_phone=OWNER_PHONE,
        owner_phone_raw=OWNER_PHONE_RAW, owner_email=OWNER_EMAIL, site_url=SITE_URL,
    )

db.init_app(app)
migrate = Migrate(app, db)

# ── Seed data for tariffs ──────────────────────────────────────────────────────
_TARIFF_SEED = [
    ('казанское', 150, None, False),
    ('новоселезнево', 200, None, False),
    ('шадринка', 300, None, False),
    ('яровское', 300, None, False),
    ('большие ярки', 300, None, False),
    ('малые ярки', 400, None, False),
    ('гагарье', 500, None, False),
    ('сладчанка', 500, None, False),
    ('боровлянка', 600, None, False),
    ('дальнетравное', 600, None, False),
    ('ильинка', 700, None, False),
    ('кугаево', 700, None, False),
    ('чирки', 700, None, False),
    ('огнево', 800, None, False),
    ('дубынка', 900, None, False),
    ('заречка', 900, None, False),
    ('смирное', 900, None, False),
    ('афонькино', 1000, None, False),
    ('пешнево', 1000, None, False),
    ('копотилово', 1000, None, False),
    ('ченчерь', 1000, None, False),
    ('ельцово', 1000, None, False),
    ('коротаевка', 1100, None, False),
    ('грачи', 1200, None, False),
    ('паленка', 1200, None, False),
    ('новогеоргиевка', 1500, None, False),
    ('новоалександровка', 1500, None, False),
    ('челюскинцев', 1500, None, False),
    ('викторовка', 1800, None, False),
    ('долматово', 1800, None, False),
    ('ишим', 2000, 3000, True),
    ('петропавловск', 5000, 7500, True),
]

with app.app_context():
    try:
        db.create_all()
    except Exception as _e:
        print(f'[DB] create_all skipped (tables already exist): {_e}')

    # ── Manual column migrations (для обновления существующих БД) ─────────────
    _migrations = [
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS comment TEXT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment VARCHAR(20) DEFAULT 'cash'",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS from_lat FLOAT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS from_lon FLOAT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS to_lat FLOAT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS to_lon FLOAT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS ride_type VARCHAR(20) DEFAULT 'individual'",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_price INTEGER",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS car_model VARCHAR(100)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS car_color VARCHAR(50)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS car_plate VARCHAR(20)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS phone VARCHAR(20)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS balance INTEGER DEFAULT 0",
        "ALTER TABLE reviews ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'review'",
        "ALTER TABLE driver_applications ADD COLUMN IF NOT EXISTS work_from VARCHAR(10)",
        "ALTER TABLE driver_applications ADD COLUMN IF NOT EXISTS work_to VARCHAR(10)",
        "ALTER TABLE driver_applications ADD COLUMN IF NOT EXISTS work_days VARCHAR(100)",
        "ALTER TABLE driver_applications ADD COLUMN IF NOT EXISTS route_type VARCHAR(20)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS work_from VARCHAR(10)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS work_to VARCHAR(10)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS work_days VARCHAR(100)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS route_type VARCHAR(20)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS max_id VARCHAR(100)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS messenger VARCHAR(20) DEFAULT 'telegram'",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS telegram_username VARCHAR(100)",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS distance_km FLOAT",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS duration_min INTEGER",
        "ALTER TABLE orders ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT FALSE",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS driver_pin VARCHAR(20)",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS regulations_accepted BOOLEAN DEFAULT FALSE",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS regulations_accepted_at TIMESTAMP",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS online_at TIMESTAMP",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS chat_seen_group TIMESTAMP",
        "ALTER TABLE drivers ADD COLUMN IF NOT EXISTS chat_seen_direct TIMESTAMP",
    ]
    for _sql in _migrations:
        try:
            with db.engine.connect() as _conn:
                _conn.execute(text(_sql))
                _conn.commit()
        except Exception:
            pass

    # ── Seed tariffs if table is empty ────────────────────────────────────────
    if Tariff.query.count() == 0:
        for dest, price, rt_price, intercity in _TARIFF_SEED:
            db.session.add(Tariff(
                destination=dest, price=price,
                round_trip_price=rt_price, intercity=intercity,
            ))
        db.session.commit()


# ── Jinja фильтр: UTC → UTC+5 ────────────────────────────────────────────────
@app.template_filter('ekb')
def ekb_time(dt):
    if not dt:
        return '—'
    return (dt + timedelta(hours=5)).strftime('%d.%m.%Y %H:%M')


# ── Helpers ───────────────────────────────────────────────────────────────────
def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('admin'):
            return redirect(url_for('admin_login'))
        return f(*args, **kwargs)
    return decorated


def _log(action, actor='admin', order_id=None, details=None):
    """Write a dispatcher action log entry."""
    try:
        db.session.add(DispatchLog(action=action, actor=actor,
                                   order_id=order_id, details=details))
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        print(f'[LOG] {e}')


def _send_push_to_all(title, body, url='/admin/dispatcher'):
    """Send a Web Push notification to all subscribed clients."""
    if not VAPID_PRIVATE_KEY or not VAPID_PUBLIC_KEY:
        return
    try:
        from pywebpush import webpush, WebPushException
        subs = PushSubscription.query.all()
        dead = []
        for sub in subs:
            try:
                webpush(
                    subscription_info={
                        'endpoint': sub.endpoint,
                        'keys': {'p256dh': sub.p256dh, 'auth': sub.auth},
                    },
                    data=_json_mod.dumps({'title': title, 'body': body, 'url': url}),
                    vapid_private_key=VAPID_PRIVATE_KEY,
                    vapid_claims={'sub': VAPID_EMAIL},
                )
            except Exception as _pe:
                err_str = str(_pe)
                if '410' in err_str or '404' in err_str:
                    dead.append(sub.id)
        for dead_id in dead:
            PushSubscription.query.filter_by(id=dead_id).delete()
        if dead:
            db.session.commit()
    except ImportError:
        pass
    except Exception as e:
        print(f'[PUSH] {e}')


# ── Public routes ─────────────────────────────────────────────────────────────
@app.route('/')
def index():
    reviews = (
        Review.query.filter_by(approved=True, type='review')
        .order_by(Review.created_at.desc()).limit(12).all()
    )
    bg = request.args.get('bg', '')
    hero_bg = f'/static/img/test-bg{bg}.jpg' if bg in ('1', '2') else '/static/img/hero-bg.jpg'
    no_map = request.args.get('nomap') == '1'
    return render_template('index.html', reviews=reviews, yandex_maps_key=YANDEX_MAPS_KEY,
                           hero_bg=hero_bg, no_map=no_map)


@app.route('/robots.txt')
def robots_txt():
    host = SITE_URL.split('://', 1)[-1]
    lines = [
        'User-agent: *',
        'Allow: /',
        'Disallow: /admin',
        'Disallow: /a',
        'Disallow: /driver',
        'Disallow: /api',
        'Disallow: /order',
        'Disallow: /webhook',
        'Disallow: /download',
        '',
        f'Host: {host}',
        f'Sitemap: {SITE_URL}/sitemap.xml',
        '',
    ]
    return Response('\n'.join(lines), mimetype='text/plain')


@app.route('/sitemap.xml')
def sitemap_xml():
    today = datetime.utcnow().strftime('%Y-%m-%d')
    pages = [
        ('/',        '1.0', 'daily'),
        ('/join',    '0.6', 'monthly'),
        ('/offer',   '0.3', 'yearly'),
        ('/privacy', '0.3', 'yearly'),
    ]
    urls = '\n'.join(
        f'  <url><loc>{SITE_URL}{path}</loc><lastmod>{today}</lastmod>'
        f'<changefreq>{freq}</changefreq><priority>{prio}</priority></url>'
        for path, prio, freq in pages
    )
    xml = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f'{urls}\n'
        '</urlset>\n'
    )
    return Response(xml, mimetype='application/xml')


@app.route('/order', methods=['POST'])
def create_order():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'Нет данных'}), 400

    phone        = str(data.get('phone', '')).strip()
    from_address = str(data.get('from_address', '')).strip()
    to_address   = str(data.get('to_address', '')).strip()
    _comment_raw = data.get('comment')
    comment      = str(_comment_raw).strip() if _comment_raw else ''
    payment_raw  = str(data.get('payment', 'cash')).strip()
    payment      = 'transfer' if payment_raw == 'transfer' else 'cash'
    ride_type_raw = str(data.get('ride_type', 'individual')).strip()
    ride_type    = 'shared' if ride_type_raw == 'shared' else 'individual'

    _ep = data.get('estimated_price')
    try:
        estimated_price = int(_ep) if _ep not in (None, '', 'null') else None
    except (ValueError, TypeError):
        estimated_price = None

    if not phone:
        return jsonify({'error': 'Укажите телефон'}), 400
    if not from_address:
        return jsonify({'error': 'Укажите откуда ехать'}), 400
    if not to_address:
        return jsonify({'error': 'Укажите куда ехать'}), 400

    # Защита от двойной отправки — тот же телефон + маршрут за последние 2 минуты
    _recent_cutoff = datetime.utcnow() - timedelta(minutes=2)
    _dup = Order.query.filter(
        Order.phone == phone,
        Order.from_address == from_address,
        Order.to_address == to_address,
        Order.created_at >= _recent_cutoff,
    ).first()
    if _dup:
        return jsonify({'success': True, 'order_id': _dup.id, 'duplicate': True})

    def _float_or_none(key):
        v = data.get(key)
        try:
            return float(v) if v not in (None, '', 'null') else None
        except (ValueError, TypeError):
            return None

    def _int_or_none(key):
        v = data.get(key)
        try:
            return int(float(v)) if v not in (None, '', 'null') else None
        except (ValueError, TypeError):
            return None

    scheduled_at = None
    raw_dt = data.get('scheduled_at', '')
    if raw_dt:
        try:
            scheduled_at = datetime.fromisoformat(raw_dt)
        except (ValueError, TypeError):
            pass

    order = Order(
        phone=phone, from_address=from_address,
        from_lat=_float_or_none('from_lat'), from_lon=_float_or_none('from_lon'),
        to_address=to_address,
        to_lat=_float_or_none('to_lat'), to_lon=_float_or_none('to_lon'),
        comment=comment or None, payment=payment, ride_type=ride_type,
        estimated_price=estimated_price, scheduled_at=scheduled_at,
        distance_km=_float_or_none('distance_km'),
        duration_min=_int_or_none('duration_min'),
    )
    db.session.add(order)
    db.session.commit()

    _log('order_created', actor='client', order_id=order.id,
         details=f'{from_address} → {to_address}')
    telegram_bot.notify_drivers(order)
    import max_bot as _max_bot; _max_bot.notify_drivers(order)
    _send_push_to_all('🚖 Новый заказ', f'{order.from_address} → {order.to_address}', '/admin/dispatcher')
    _send_push_to_driver_subs('🚖 Новый заказ!', f'{order.from_address} → {order.to_address}')

    return jsonify({'success': True, 'order_id': order.id})


@app.route('/sw.js')
def service_worker():
    v = STATIC_VER
    js = f"""const CACHE = 'dispatcher-v{v}';
const STATIC = [
  '/admin/dispatcher',
  '/static/css/dispatcher.css?v={v}',
  '/static/js/dispatcher.js?v={v}',
];

self.addEventListener('install', e => {{
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(STATIC).catch(() => {{}}))
  );
  self.skipWaiting();
}});

self.addEventListener('activate', e => {{
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
}});

self.addEventListener('fetch', e => {{
  const url = new URL(e.request.url);
  if (url.pathname.startsWith('/api/')) return;
  e.respondWith(
    fetch(e.request).catch(() => caches.match(e.request))
  );
}});

self.addEventListener('push', e => {{
  let data = {{}};
  try {{ data = e.data ? e.data.json() : {{}}; }} catch(err) {{}}
  const title = data.title || 'Казанское Такси';
  const body  = data.body  || 'Новое уведомление';
  const url   = data.url   || '/admin/dispatcher';
  e.waitUntil(
    self.registration.showNotification(title, {{
      body,
      icon: '/static/img/icon-192.png',
      badge: '/static/img/icon-192.png',
      data: {{ url }},
      vibrate: [200, 100, 200],
      requireInteraction: false,
    }})
  );
}});

self.addEventListener('notificationclick', e => {{
  e.notification.close();
  e.waitUntil(
    clients.matchAll({{ type: 'window', includeUncontrolled: true }}).then(list => {{
      for (const client of list) {{
        if (client.url.includes('/admin') && 'focus' in client) return client.focus();
      }}
      if (clients.openWindow) return clients.openWindow(e.notification.data.url || '/admin/dispatcher');
    }})
  );
}});
"""
    resp = make_response(js, 200)
    resp.headers['Content-Type'] = 'application/javascript'
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    return resp


@app.route('/privacy')
def privacy():
    return render_template('privacy.html', **legal_ctx())


@app.route('/offer')
def offer():
    return render_template('offer.html', **legal_ctx())


@app.route('/review', methods=['POST'])
def create_review():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'Нет данных'}), 400
    name = str(data.get('name', '')).strip()
    text = str(data.get('text', '')).strip()
    if not name or not text:
        return jsonify({'error': 'Имя и текст обязательны'}), 400
    if len(name) > 100:
        return jsonify({'error': 'Имя слишком длинное'}), 400
    if len(text) > 1000:
        return jsonify({'error': 'Отзыв слишком длинный (макс. 1000 символов)'}), 400
    review_type = str(data.get('type', 'review')).strip()
    if review_type not in ('review', 'wish'):
        review_type = 'review'
    db.session.add(Review(name=name, text=text, type=review_type))
    db.session.commit()
    return jsonify({'success': True})


# ── Telegram webhook ──────────────────────────────────────────────────────────
@app.route('/webhook/<token>', methods=['POST'])
def telegram_webhook(token):
    tg_token = os.environ.get('TELEGRAM_TOKEN', '')
    if not tg_token or token != tg_token:
        return jsonify({'error': 'Unauthorized'}), 403
    update = request.get_json(silent=True)
    if update:
        telegram_bot.handle_update(update)
    return jsonify({'ok': True})


# ── MAX webhook ───────────────────────────────────────────────────────────────
@app.route('/webhook-max/<token>', methods=['POST'])
def max_webhook(token):
    if not MAX_BOT_TOKEN or token != MAX_BOT_TOKEN:
        return jsonify({'error': 'Unauthorized'}), 403
    update = request.get_json(silent=True)
    if update:
        import max_bot as _max_bot
        _max_bot.handle_update(update)
    return jsonify({'ok': True})


# ── Admin: auth ───────────────────────────────────────────────────────────────
@app.route('/a', methods=['GET', 'POST'])
def admin_login():
    if session.get('admin'):
        return redirect(url_for('admin_dashboard'))
    error = None
    if request.method == 'POST':
        if request.form.get('password') == ADMIN_PASSWORD:
            session['admin'] = True
            return redirect(url_for('admin_orders'))
        error = 'Неверный пароль'
    return render_template('admin_login.html', error=error)


@app.route('/admin/logout')
def admin_logout():
    session.pop('admin', None)
    return redirect(url_for('admin_login'))


# ── Admin: webhook setup ──────────────────────────────────────────────────────
@app.route('/admin/set_webhook')
@admin_required
def set_webhook():
    import requests as req
    tg_token = os.environ.get('TELEGRAM_TOKEN', '')
    if not tg_token:
        return jsonify({'error': 'TELEGRAM_TOKEN не задан'}), 400
    host = request.host_url.rstrip('/')
    host = host.replace('http://', 'https://', 1)
    webhook_url = f"{host}/webhook/{tg_token}"
    resp = req.post(
        f'https://api.telegram.org/bot{tg_token}/setWebhook',
        json={'url': webhook_url}, timeout=10,
    )
    return jsonify({'webhook_url': webhook_url, 'telegram_response': resp.json()})


# ── Driver status helper ──────────────────────────────────────────────────────
def compute_driver_statuses(drivers):
    result = {}
    for d in drivers:
        active = (
            Order.query
            .filter_by(driver_telegram_id=d.telegram_id, status='accepted')
            .order_by(Order.created_at.desc()).first()
        )
        if active:
            if active.scheduled_at and active.scheduled_at > datetime.utcnow() + timedelta(hours=1):
                result[d.id] = {'label': 'Свободен', 'level': 'free'}
                continue
            mins = int((datetime.utcnow() - active.created_at).total_seconds() / 60)
            if mins < 90:
                result[d.id] = {'label': f'Выполняет заказ · {mins} мин', 'level': 'busy'}
            else:
                result[d.id] = {'label': f'Возможно занят · {mins} мин', 'level': 'maybe'}
            continue
        recent = (
            Order.query
            .filter_by(driver_telegram_id=d.telegram_id, status='completed')
            .order_by(Order.created_at.desc()).first()
        )
        if recent:
            mins = int((datetime.utcnow() - recent.created_at).total_seconds() / 60)
            if mins < 20:
                result[d.id] = {'label': f'Только завершил · {mins} мин назад', 'level': 'maybe'}
                continue
        result[d.id] = {'label': 'Свободен', 'level': 'free'}
    return result


# ── Admin: dashboard ─────────────────────────────────────────────────────────
@app.route('/admin')
@app.route('/admin/dashboard')
@admin_required
def admin_dashboard():
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    total_new       = Order.query.filter_by(status='new').count()
    total_accepted  = Order.query.filter_by(status='accepted').count()
    today_all       = Order.query.filter(Order.created_at >= today_start).count()
    today_completed = Order.query.filter(
        Order.created_at >= today_start, Order.status == 'completed').count()
    today_accepted  = Order.query.filter(
        Order.created_at >= today_start, Order.status != 'new').count()
    active_drivers  = Driver.query.filter_by(active=True).count()
    conversion      = round(today_accepted / today_all * 100) if today_all else 0
    recent_orders   = (
        Order.query.filter_by(status='new')
        .order_by(Order.created_at.desc()).limit(5).all()
    )
    return render_template('admin_dashboard.html',
        total_new=total_new, total_accepted=total_accepted,
        today_all=today_all, today_completed=today_completed,
        active_drivers=active_drivers, conversion=conversion,
        recent_orders=recent_orders,
    )


# ── Admin: orders ─────────────────────────────────────────────────────────────
@app.route('/admin/orders/create', methods=['POST'])
@admin_required
def admin_create_order():
    from_address  = request.form.get('from_address', '').strip()
    to_address    = request.form.get('to_address', '').strip()
    phone         = request.form.get('phone', '').strip()
    comment       = request.form.get('comment', '').strip() or None
    ride_type     = request.form.get('ride_type', 'individual')
    payment       = request.form.get('payment', 'cash')
    driver_id     = request.form.get('driver_id', type=int)
    raw_dt        = request.form.get('scheduled_at', '').strip()
    ep_raw        = request.form.get('estimated_price', '')

    if not (from_address and to_address and phone):
        return redirect(url_for('admin_orders'))

    try:
        estimated_price = int(ep_raw) if ep_raw else None
    except (ValueError, TypeError):
        estimated_price = None

    scheduled_at = None
    if raw_dt:
        try:
            scheduled_at = datetime.fromisoformat(raw_dt) - timedelta(hours=5)
        except (ValueError, TypeError):
            pass

    try:
        order = Order(
            phone=phone, from_address=from_address,
            from_lat=0.0, from_lon=0.0, to_address=to_address,
            to_lat=0.0, to_lon=0.0, comment=comment,
            payment=payment, ride_type=ride_type,
            estimated_price=estimated_price, scheduled_at=scheduled_at, status='new',
        )
        db.session.add(order)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        return f'Ошибка базы данных: {e}', 500

    _log('order_created', actor='admin', order_id=order.id,
         details=f'{from_address} → {to_address}')

    try:
        if driver_id:
            driver = Driver.query.filter_by(id=driver_id).first()
            if driver:
                order.driver_telegram_id = driver.telegram_id
                order.driver_name = driver.name
                order.status = 'accepted'
                db.session.commit()
                _log('order_assigned', actor='admin', order_id=order.id,
                     details=f'Водитель: {driver.name}')
                telegram_bot.notify_driver_assigned(order, driver)
        else:
            telegram_bot.notify_drivers(order)
            import max_bot as _max_bot; _max_bot.notify_drivers(order)
    except Exception as e:
        print(f'[admin_create_order] notify error: {e}')

    return redirect(url_for('admin_orders'))


@app.route('/admin/orders')
@admin_required
def admin_orders():
    status     = request.args.get('status', '')
    search_phone = request.args.get('phone', '').strip()
    date_from  = request.args.get('date_from', '').strip()
    date_to    = request.args.get('date_to', '').strip()
    drv_filter = request.args.get('driver_id', '', type=str).strip()
    page       = request.args.get('page', 1, type=int)
    per_page   = 25

    q = Order.query
    if status:
        q = q.filter_by(status=status)
    if search_phone:
        q = q.filter(Order.phone.contains(search_phone))
    if date_from:
        try:
            q = q.filter(Order.created_at >= datetime.fromisoformat(date_from))
        except (ValueError, TypeError):
            pass
    if date_to:
        try:
            q = q.filter(Order.created_at <= datetime.fromisoformat(date_to + 'T23:59:59'))
        except (ValueError, TypeError):
            pass
    if drv_filter:
        q = q.filter(Order.driver_name.contains(drv_filter))

    pagination = q.order_by(Order.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    orders  = pagination.items
    drivers = Driver.query.filter_by(active=True).order_by(Driver.name).all()
    driver_statuses = compute_driver_statuses(drivers)
    intercity_keys = {t.destination.lower() for t in Tariff.query.filter_by(intercity=True, active=True).all()}

    return render_template('admin_orders.html',
        orders=orders, pagination=pagination,
        current_status=status, drivers=drivers,
        driver_statuses=driver_statuses,
        intercity_keys=intercity_keys,
        search_phone=search_phone, date_from=date_from,
        date_to=date_to, drv_filter=drv_filter,
    )


@app.route('/admin/orders/<int:order_id>/assign', methods=['POST'])
@admin_required
def assign_driver_to_order(order_id):
    order = Order.query.get_or_404(order_id)
    driver_id = request.form.get('driver_id', type=int)
    if driver_id:
        driver = Driver.query.get(driver_id)
        if driver:
            order.driver_telegram_id = driver.telegram_id
            order.driver_name = driver.name
            order.status = 'accepted'
            db.session.commit()
            _log('order_assigned', actor='admin', order_id=order.id,
                 details=f'Водитель: {driver.name}')
            telegram_bot.notify_driver_assigned(order, driver)
    return redirect(url_for('admin_orders', status=request.args.get('status', '')))


@app.route('/admin/orders/<int:order_id>/status', methods=['POST'])
@admin_required
def update_order_status(order_id):
    order = Order.query.get_or_404(order_id)
    new_status = request.form.get('status', '')
    if new_status in ('new', 'accepted', 'completed'):
        old_status = order.status
        order.status = new_status

        # сброс назначения водителя при возврате в «новый»
        if new_status == 'new':
            order.driver_telegram_id = None
            order.driver_name = None
            order.reminder_sent = False

        # начисляем заработок водителю при подтверждении завершения
        if new_status == 'completed' and old_status != 'completed' and order.driver_telegram_id:
            # Если диспетчер передал фактическую цену — используем её
            try:
                actual = int(request.form.get('actual_price', '') or 0)
            except (ValueError, TypeError):
                actual = 0
            amount = actual or order.estimated_price or 0
            if actual and actual != order.estimated_price:
                order.estimated_price = actual
            if amount > 0:
                tid = order.driver_telegram_id
                driver = (Driver.query.filter_by(telegram_id=tid).first()
                          if not tid.startswith('max:') else
                          Driver.query.filter_by(max_id=tid[4:]).first())
                if driver:
                    commission = INTERCITY_COMMISSION if telegram_bot._is_intercity(order) else 0
                    driver.balance = (driver.balance or 0) + amount - commission
                    if commission:
                        _log('commission', actor='system', order_id=order.id,
                             details=f'Комиссия межгород: -{commission} ₽ ({driver.name})')

        db.session.commit()
        _log('status_changed', actor='admin', order_id=order.id,
             details=f'{old_status} → {new_status}')

        # Re-notify водителей когда заказ возвращён в очередь
        if new_status == 'new' and old_status in ('accepted', 'completed'):
            try:
                telegram_bot.notify_drivers(order)
                _send_push_to_driver_subs('🔄 Заказ снова свободен', f'{order.from_address} → {order.to_address}')
            except Exception as _e:
                print(f'[notify] re-notify error: {_e}')

    # AJAX or form submit — return JSON if X-Requested-With header present
    if request.headers.get('X-Requested-With') == 'XMLHttpRequest':
        return jsonify({'ok': True})
    return redirect(url_for('admin_orders', status=request.args.get('status', '')))


# ── Admin: dispatcher PWA ────────────────────────────────────────────────────
@app.route('/admin/dispatcher')
@admin_required
def admin_dispatcher():
    return render_template('admin_dispatcher.html')


@app.route('/api/dispatcher')
@admin_required
def api_dispatcher():
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    def order_dict(o):
        sched = None
        if o.scheduled_at:
            sched = (o.scheduled_at + timedelta(hours=5)).strftime('%d.%m %H:%M')
        return {
            'id':           o.id,
            'status':       o.status,
            'from_address': o.from_address,
            'to_address':   o.to_address,
            'phone':        o.phone,
            'comment':      o.comment or '',
            'payment':      o.payment or 'cash',
            'scheduled_at': sched,
            'driver_name':  o.driver_name or '',
            'driver_car':   (lambda _d: _d.car_info or '' if _d else '')(
                                Driver.query.filter_by(telegram_id=o.driver_telegram_id).first()
                                if o.driver_telegram_id else None),
            'ride_type':    o.ride_type or 'individual',
            'estimated_price': o.estimated_price,
            'has_coords':   o.has_coords,
            'created_at':   (o.created_at + timedelta(hours=5)).strftime('%d.%m %H:%M'),
        }

    drivers  = Driver.query.filter_by(active=True).order_by(Driver.name).all()
    statuses = compute_driver_statuses(drivers)

    recent_log = (
        DispatchLog.query
        .order_by(DispatchLog.created_at.desc())
        .limit(30).all()
    )

    return jsonify({
        'orders_new':       [order_dict(o) for o in Order.query.filter_by(status='new').order_by(Order.created_at.desc()).all()],
        'orders_accepted':  [order_dict(o) for o in Order.query.filter_by(status='accepted').order_by(Order.created_at.desc()).all()],
        'orders_completed': [order_dict(o) for o in Order.query.filter_by(status='completed').order_by(Order.created_at.desc()).limit(20).all()],
        'drivers': [{
            'id': d.id, 'name': d.name, 'telegram_id': d.telegram_id,
            'car_info': d.car_info or '', 'phone': d.phone or '',
        } for d in drivers],
        'driver_statuses': {str(k): v for k, v in statuses.items()},
        'today_count':      Order.query.filter(Order.created_at >= today_start).count(),
        'active_drivers':   len(drivers),
        'recent_log': [{
            'action':     e.action,
            'actor':      e.actor or '',
            'order_id':   e.order_id,
            'details':    e.details or '',
            'created_at': (e.created_at + timedelta(hours=5)).strftime('%d.%m %H:%M'),
        } for e in recent_log],
    })


# ── Admin: order edit ────────────────────────────────────────────────────────
@app.route('/admin/orders/<int:order_id>/edit', methods=['POST'])
@admin_required
def edit_order(order_id):
    order = Order.query.get_or_404(order_id)
    fa = str(request.form.get('from_address', '')).strip()
    ta = str(request.form.get('to_address', '')).strip()
    if fa: order.from_address = fa
    if ta: order.to_address = ta
    ph = str(request.form.get('phone', '')).strip()
    if ph: order.phone = ph
    cmt = request.form.get('comment', '')
    order.comment = cmt.strip() or None
    pay = request.form.get('payment', '')
    if pay in ('cash', 'transfer'): order.payment = pay
    rt = request.form.get('ride_type', '')
    if rt in ('individual', 'shared'): order.ride_type = rt
    try:
        ep = int(request.form.get('estimated_price', '') or 0)
        if ep > 0: order.estimated_price = ep
        elif request.form.get('estimated_price', '') == '': order.estimated_price = None
    except (ValueError, TypeError):
        pass
    raw_dt = request.form.get('scheduled_at', '').strip()
    if raw_dt:
        try:
            order.scheduled_at = datetime.fromisoformat(raw_dt)
        except (ValueError, TypeError):
            pass
    elif raw_dt == '':
        order.scheduled_at = None
    db.session.commit()
    _log('order_edited', actor='admin', order_id=order.id,
         details=f'{order.from_address} → {order.to_address}')
    back = request.args.get('status', '')
    return redirect(url_for('admin_orders', status=back))


# ── Delete single order ───────────────────────────────────────────────────────
@app.route('/admin/orders/<int:order_id>/delete', methods=['POST'])
@admin_required
def delete_order(order_id):
    order = Order.query.get_or_404(order_id)
    back  = request.args.get('status', '')
    db.session.delete(order)
    db.session.commit()
    _log('order_deleted', actor='admin', order_id=order_id,
         details=f'{order.from_address} → {order.to_address}')
    return redirect(url_for('admin_orders', status=back))


# ── Admin: danger zone (reset) ────────────────────────────────────────────────
@app.route('/admin/reset', methods=['GET', 'POST'])
@admin_required
def admin_reset():
    done = []
    if request.method == 'POST':
        action = request.form.get('action', '')
        if action == 'delete_orders':
            n = Order.query.count()
            Order.query.delete()
            db.session.commit()
            _log('reset', actor='admin', details=f'Удалено {n} заказов')
            done.append(f'Удалено {n} заказов')
        elif action == 'reset_balances':
            drivers = Driver.query.all()
            for d in drivers:
                d.balance = 0
                d.regulations_accepted = False
                d.regulations_accepted_at = None
            db.session.commit()
            _log('reset', actor='admin', details='Балансы и регламенты водителей обнулены')
            done.append(f'Балансы {len(drivers)} водителей обнулены')
        elif action == 'delete_all':
            n_orders = Order.query.count()
            n_log    = DispatchLog.query.count()
            Order.query.delete()
            DispatchLog.query.delete()
            for d in Driver.query.all():
                d.balance = 0
            db.session.commit()
            _log('reset', actor='admin', details='Полный сброс: заказы + лог + балансы')
            done.append(f'Удалено {n_orders} заказов, {n_log} записей лога, балансы обнулены')
    orders_count   = Order.query.count()
    drivers_count  = Driver.query.count()
    log_count      = DispatchLog.query.count()
    return render_template('admin_reset.html',
        done=done,
        orders_count=orders_count,
        drivers_count=drivers_count,
        log_count=log_count,
    )


# ── Driver push notifications ─────────────────────────────────────────────────
def _send_push_to_driver_subs(title, body, url='/driver/'):
    """Send Web Push to all subscribed driver browsers."""
    if not VAPID_PRIVATE_KEY or not VAPID_PUBLIC_KEY:
        return
    try:
        from pywebpush import webpush, WebPushException
        subs = DriverPushSubscription.query.all()
        dead = []
        for sub in subs:
            try:
                webpush(
                    subscription_info={
                        'endpoint': sub.endpoint,
                        'keys': {'p256dh': sub.p256dh, 'auth': sub.auth},
                    },
                    data=_json_mod.dumps({'title': title, 'body': body, 'url': url}),
                    vapid_private_key=VAPID_PRIVATE_KEY,
                    vapid_claims={'sub': VAPID_EMAIL},
                )
            except Exception as _pe:
                if '410' in str(_pe) or '404' in str(_pe):
                    dead.append(sub.id)
        for did in dead:
            DriverPushSubscription.query.filter_by(id=did).delete()
        if dead:
            db.session.commit()
    except ImportError:
        pass
    except Exception as e:
        print(f'[DRIVER-PUSH] {e}')


def _send_push_to_one_driver(driver_id, title, body, url='/driver/'):
    """Send Web Push only to a specific driver's subscribed browsers."""
    if not VAPID_PRIVATE_KEY or not VAPID_PUBLIC_KEY:
        return
    try:
        from pywebpush import webpush
        subs = DriverPushSubscription.query.filter_by(driver_id=driver_id).all()
        dead = []
        for sub in subs:
            try:
                webpush(
                    subscription_info={
                        'endpoint': sub.endpoint,
                        'keys': {'p256dh': sub.p256dh, 'auth': sub.auth},
                    },
                    data=_json_mod.dumps({'title': title, 'body': body, 'url': url}),
                    vapid_private_key=VAPID_PRIVATE_KEY,
                    vapid_claims={'sub': VAPID_EMAIL},
                )
            except Exception as _pe:
                if '410' in str(_pe) or '404' in str(_pe):
                    dead.append(sub.id)
        for did in dead:
            DriverPushSubscription.query.filter_by(id=did).delete()
        if dead:
            db.session.commit()
    except ImportError:
        pass
    except Exception as e:
        print(f'[DRIVER-PUSH-ONE] {e}')


# ══════════════════════════════════════════════════════════════════════════════
# ВСТРОЕННЫЙ ЧАТ (общий + личные с водителями)
# ══════════════════════════════════════════════════════════════════════════════
def _msg_dict(m):
    return {
        'id': m.id,
        'room': m.room,
        'sender': m.sender,
        'driver_id': m.driver_id,
        'author': m.author_name or ('Диспетчер' if m.sender == 'admin' else 'Водитель'),
        'body': m.body,
        'ts': (m.created_at or datetime.utcnow()).isoformat() + 'Z',
    }


# ── Админка: чат ──────────────────────────────────────────────────────────────
@app.route('/admin/chat')
@admin_required
def admin_chat():
    return render_template('admin_chat.html')


@app.route('/admin/chat/rooms')
@admin_required
def admin_chat_rooms():
    drivers = Driver.query.filter_by(active=True).order_by(Driver.name).all()
    rooms = []

    # Общий чат
    g_last = ChatMessage.query.filter_by(room='group').order_by(ChatMessage.id.desc()).first()
    g_unread = ChatMessage.query.filter_by(room='group', sender='driver', read_admin=False).count()
    rooms.append({
        'room': 'group', 'name': 'Общий чат', 'kind': 'group',
        'online': sum(1 for d in drivers if d.is_online),
        'total': len(drivers),
        'last': (g_last.body[:60] if g_last else ''),
        'last_ts': ((g_last.created_at.isoformat() + 'Z') if g_last and g_last.created_at else ''),
        'unread': g_unread,
    })

    # Личные чаты с каждым водителем
    for d in drivers:
        room = f'd{d.id}'
        last = ChatMessage.query.filter_by(room=room).order_by(ChatMessage.id.desc()).first()
        unread = ChatMessage.query.filter_by(room=room, sender='driver', read_admin=False).count()
        rooms.append({
            'room': room, 'name': d.name, 'kind': 'direct', 'driver_id': d.id,
            'online': bool(d.is_online),
            'last': (last.body[:60] if last else ''),
            'last_ts': ((last.created_at.isoformat() + 'Z') if last and last.created_at else ''),
            'unread': unread,
        })
    return jsonify({'rooms': rooms})


@app.route('/admin/chat/messages')
@admin_required
def admin_chat_messages():
    room  = request.args.get('room', 'group')
    after = request.args.get('after', 0, type=int)
    q = ChatMessage.query.filter(ChatMessage.room == room, ChatMessage.id > after)
    msgs = q.order_by(ChatMessage.id.asc()).limit(200).all()
    return jsonify({'messages': [_msg_dict(m) for m in msgs]})


@app.route('/admin/chat/send', methods=['POST'])
@admin_required
def admin_chat_send():
    data = request.get_json(silent=True) or {}
    room = str(data.get('room', 'group')).strip()
    body = str(data.get('body', '')).strip()
    if not body:
        return jsonify({'error': 'Пустое сообщение'}), 400
    if len(body) > 2000:
        body = body[:2000]

    driver_id = None
    if room.startswith('d'):
        try:
            driver_id = int(room[1:])
        except ValueError:
            return jsonify({'error': 'Некорректная комната'}), 400
        if not Driver.query.get(driver_id):
            return jsonify({'error': 'Водитель не найден'}), 404
    elif room != 'group':
        return jsonify({'error': 'Некорректная комната'}), 400

    m = ChatMessage(room=room, sender='admin', driver_id=driver_id,
                    author_name='Диспетчер', body=body, read_admin=True)
    db.session.add(m)
    db.session.commit()

    # Push водителям
    try:
        if room == 'group':
            _send_push_to_driver_subs('💬 Общий чат', body[:120], '/driver/?tab=chat')
        elif driver_id:
            _send_push_to_one_driver(driver_id, '💬 Диспетчер', body[:120], '/driver/?tab=chat')
    except Exception as _e:
        print(f'[CHAT-PUSH] {_e}')

    return jsonify({'ok': True, 'message': _msg_dict(m)})


@app.route('/admin/chat/read', methods=['POST'])
@admin_required
def admin_chat_read():
    data = request.get_json(silent=True) or {}
    room = str(data.get('room', '')).strip()
    if room:
        ChatMessage.query.filter_by(room=room, sender='driver', read_admin=False).update(
            {'read_admin': True})
        db.session.commit()
    return jsonify({'ok': True})


def _driver_chat_unread(driver):
    """Непрочитанные для водителя: (общий, личный)."""
    g_seen = driver.chat_seen_group or datetime(2000, 1, 1)
    d_seen = driver.chat_seen_direct or datetime(2000, 1, 1)
    unread_group = ChatMessage.query.filter(
        ChatMessage.room == 'group',
        ChatMessage.created_at > g_seen,
        db.or_(ChatMessage.sender == 'admin', ChatMessage.driver_id != driver.id),
    ).count()
    unread_direct = ChatMessage.query.filter(
        ChatMessage.room == f'd{driver.id}',
        ChatMessage.sender == 'admin',
        ChatMessage.created_at > d_seen,
    ).count()
    return unread_group, unread_direct


# ── Admin: reviews ────────────────────────────────────────────────────────────
@app.route('/admin/reviews')
@admin_required
def admin_reviews():
    type_filter = request.args.get('type', 'all')
    q = Review.query.order_by(Review.approved.asc(), Review.created_at.desc())
    if type_filter == 'review':
        q = q.filter_by(type='review')
    elif type_filter == 'wish':
        q = q.filter_by(type='wish')
    reviews = q.all()
    counts = {
        'all': Review.query.count(),
        'review': Review.query.filter_by(type='review').count(),
        'wish': Review.query.filter_by(type='wish').count(),
    }
    return render_template('admin_reviews.html', reviews=reviews, type_filter=type_filter, counts=counts)


@app.route('/admin/reviews/<int:review_id>/approve', methods=['POST'])
@admin_required
def approve_review(review_id):
    review = Review.query.get_or_404(review_id)
    review.approved = True
    db.session.commit()
    return redirect(url_for('admin_reviews'))


@app.route('/admin/reviews/<int:review_id>/delete', methods=['POST'])
@admin_required
def delete_review(review_id):
    review = Review.query.get_or_404(review_id)
    db.session.delete(review)
    db.session.commit()
    return redirect(url_for('admin_reviews'))


# ── Admin: drivers ────────────────────────────────────────────────────────────
@app.route('/admin/drivers')
@admin_required
def admin_drivers():
    drivers = Driver.query.order_by(Driver.name).all()

    # Today's window in UTC (UTC+5 zone: today starts at 19:00 UTC prev day)
    _now_utc = datetime.utcnow()
    _today_ekb_start = (_now_utc + timedelta(hours=5)).replace(hour=0, minute=0, second=0, microsecond=0)
    _today_utc_start = _today_ekb_start - timedelta(hours=5)

    driver_stats = {}
    for d in drivers:
        tids = [d.telegram_id, f'app:{d.id}'] if d.telegram_id else [f'app:{d.id}']
        total     = Order.query.filter(Order.driver_telegram_id.in_(tids)).count()
        completed = Order.query.filter(Order.driver_telegram_id.in_(tids), Order.status=='completed').count()
        revenue   = db.session.query(db.func.sum(Order.estimated_price)).filter(
            Order.driver_telegram_id.in_(tids),
            Order.status == 'completed',
        ).scalar() or 0
        today_rev = db.session.query(db.func.sum(Order.estimated_price)).filter(
            Order.driver_telegram_id.in_(tids),
            Order.status == 'completed',
            Order.created_at >= _today_utc_start,
        ).scalar() or 0
        driver_stats[d.id] = {
            'total': total, 'completed': completed,
            'revenue': revenue, 'today': today_rev,
        }

    return render_template('admin_drivers.html', drivers=drivers, driver_stats=driver_stats)


@app.route('/admin/drivers/<int:driver_id>/stats')
@admin_required
def driver_stats_page(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    # Заказы водителя за последние 90 дней (TG + приложение)
    since = datetime.utcnow() - timedelta(days=90)
    _tids = [driver.telegram_id, f'app:{driver.id}'] if driver.telegram_id else [f'app:{driver.id}']
    orders = Order.query.filter(
        Order.driver_telegram_id.in_(_tids),
        Order.created_at >= since,
    ).order_by(Order.created_at.asc()).all()

    # По дням (выручка и кол-во)
    from collections import defaultdict
    daily_revenue = defaultdict(int)
    daily_count   = defaultdict(int)
    monthly_count = defaultdict(int)
    monthly_revenue = defaultdict(int)
    for o in orders:
        day = (o.created_at + timedelta(hours=5)).strftime('%Y-%m-%d')
        mon = (o.created_at + timedelta(hours=5)).strftime('%Y-%m')
        if o.status == 'completed':
            daily_revenue[day] += o.estimated_price or 0
            monthly_revenue[mon] += o.estimated_price or 0
        daily_count[day]   += 1
        monthly_count[mon] += 1

    total_orders    = len(orders)
    total_completed = sum(1 for o in orders if o.status == 'completed')
    total_revenue   = sum(o.estimated_price or 0 for o in orders if o.status == 'completed')

    return render_template('admin_driver_stats.html',
        driver=driver,
        total_orders=total_orders,
        total_completed=total_completed,
        total_revenue=total_revenue,
        daily_revenue=dict(daily_revenue),
        daily_count=dict(daily_count),
        monthly_count=dict(monthly_count),
        monthly_revenue=dict(monthly_revenue),
    )


@app.route('/admin/drivers/add', methods=['POST'])
@admin_required
def add_driver():
    tid       = str(request.form.get('telegram_id', '')).strip()
    name      = str(request.form.get('name', '')).strip()
    phone     = str(request.form.get('phone', '')).strip() or None
    car_model = str(request.form.get('car_model', '')).strip() or None
    car_color = str(request.form.get('car_color', '')).strip() or None
    car_plate = str(request.form.get('car_plate', '')).strip() or None
    uname = str(request.form.get('telegram_username', '')).strip().lstrip('@') or None
    if tid and name:
        if not Driver.query.filter_by(telegram_id=tid).first():
            db.session.add(Driver(
                telegram_id=tid, name=name, phone=phone,
                car_model=car_model, car_color=car_color, car_plate=car_plate,
                telegram_username=uname,
            ))
            db.session.commit()
            _log('driver_added', actor='admin', details=f'{name} (TG: {tid})')
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/edit', methods=['POST'])
@admin_required
def edit_driver(driver_id):
    driver    = Driver.query.get_or_404(driver_id)
    name      = str(request.form.get('name', '')).strip()
    phone     = str(request.form.get('phone', '')).strip() or None
    car_model = str(request.form.get('car_model', '')).strip() or None
    car_color = str(request.form.get('car_color', '')).strip() or None
    car_plate = str(request.form.get('car_plate', '')).strip() or None
    # Allow updating telegram_id (but only if not already taken by another driver)
    new_tid = str(request.form.get('telegram_id', '')).strip()
    if new_tid and new_tid != driver.telegram_id:
        conflict = Driver.query.filter_by(telegram_id=new_tid).first()
        if not conflict:
            driver.telegram_id = new_tid
    if name:
        driver.name = name
    driver.phone      = phone
    driver.car_model  = car_model
    driver.car_color  = car_color
    driver.car_plate  = car_plate
    driver.work_from  = str(request.form.get('work_from', '')).strip() or None
    driver.work_to    = str(request.form.get('work_to', '')).strip() or None
    days = request.form.getlist('work_days')
    driver.work_days  = ','.join(days) if days else None
    rt = str(request.form.get('route_type', '')).strip()
    driver.route_type = rt if rt in ('local', 'intercity', 'any') else None
    driver.max_id             = str(request.form.get('max_id', '')).strip() or None
    driver.telegram_username  = str(request.form.get('telegram_username', '')).strip().lstrip('@') or None
    msg = str(request.form.get('messenger', 'telegram')).strip()
    driver.messenger  = msg if msg in ('telegram', 'max', 'both') else 'telegram'
    pin_raw = str(request.form.get('driver_pin', '')).strip()
    if pin_raw:
        driver.driver_pin = pin_raw
    db.session.commit()
    _log('driver_updated', actor='admin', details=f'{driver.name}')
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/toggle', methods=['POST'])
@admin_required
def toggle_driver(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    driver.active = not driver.active
    db.session.commit()
    _log('driver_updated', actor='admin',
         details=f'{driver.name} → {"активен" if driver.active else "неактивен"}')
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/delete', methods=['POST'])
@admin_required
def delete_driver(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    name = driver.name
    db.session.delete(driver)
    db.session.commit()
    _log('driver_deleted', actor='admin', details=name)
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/balance', methods=['POST'])
@admin_required
def edit_driver_balance(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    try:
        new_balance = int(request.form.get('balance', 0))
    except (ValueError, TypeError):
        new_balance = 0
    old_balance = driver.balance or 0
    driver.balance = max(0, new_balance)
    db.session.commit()
    _log('driver_updated', actor='admin', details=f'{driver.name}: баланс {old_balance} → {driver.balance} ₽')
    return redirect(url_for('admin_drivers'))


# ── Admin: tariffs ────────────────────────────────────────────────────────────
@app.route('/admin/tariffs')
@admin_required
def admin_tariffs():
    local     = Tariff.query.filter_by(intercity=False).order_by(Tariff.price).all()
    intercity = Tariff.query.filter_by(intercity=True).order_by(Tariff.price).all()
    return render_template('admin_tariffs.html', local=local, intercity=intercity,
                           intercity_commission=INTERCITY_COMMISSION)


@app.route('/admin/tariffs/add', methods=['POST'])
@admin_required
def add_tariff():
    dest     = str(request.form.get('destination', '')).strip().lower()
    price    = request.form.get('price', type=int)
    rt_price = request.form.get('round_trip_price', type=int)
    intercity = request.form.get('intercity') == '1'
    if dest and price:
        if not Tariff.query.filter_by(destination=dest).first():
            db.session.add(Tariff(destination=dest, price=price,
                                  round_trip_price=rt_price, intercity=intercity))
            db.session.commit()
            _log('tariff_added', actor='admin', details=f'{dest}: {price}₽')
    return redirect(url_for('admin_tariffs'))


@app.route('/admin/tariffs/<int:tariff_id>/edit', methods=['POST'])
@admin_required
def edit_tariff(tariff_id):
    t        = Tariff.query.get_or_404(tariff_id)
    dest     = str(request.form.get('destination', '')).strip().lower()
    price    = request.form.get('price', type=int)
    rt_price = request.form.get('round_trip_price', type=int)
    intercity = request.form.get('intercity') == '1'
    if dest and price:
        t.destination      = dest
        t.price            = price
        t.round_trip_price = rt_price
        t.intercity        = intercity
        db.session.commit()
        _log('tariff_updated', actor='admin', details=f'{dest}: {price}₽')
    return redirect(url_for('admin_tariffs'))


@app.route('/admin/tariffs/<int:tariff_id>/delete', methods=['POST'])
@admin_required
def delete_tariff(tariff_id):
    t = Tariff.query.get_or_404(tariff_id)
    name = t.destination
    db.session.delete(t)
    db.session.commit()
    _log('tariff_deleted', actor='admin', details=name)
    return redirect(url_for('admin_tariffs'))


@app.route('/api/tariffs')
def api_tariffs():
    """Public endpoint — returns tariff data for map.js price calculator."""
    local_tariffs = Tariff.query.filter_by(intercity=False, active=True).all()
    intercity_tariffs = Tariff.query.filter_by(intercity=True, active=True).all()
    return jsonify({
        'local': {t.destination: t.price for t in local_tariffs},
        'intercity': {
            t.destination: {
                'one_way': t.price,
                'round_trip': t.round_trip_price or t.price,
            }
            for t in intercity_tariffs
        },
    })


# ── Admin: dispatch log ───────────────────────────────────────────────────────
@app.route('/admin/log')
@admin_required
def admin_log():
    page     = request.args.get('page', 1, type=int)
    action_f = request.args.get('action', '')

    q = DispatchLog.query
    if action_f:
        q = q.filter_by(action=action_f)

    pagination = q.order_by(DispatchLog.created_at.desc()).paginate(
        page=page, per_page=50, error_out=False
    )
    actions = db.session.query(DispatchLog.action).distinct().order_by(DispatchLog.action).all()
    actions = [a[0] for a in actions]

    return render_template('admin_log.html',
        entries=pagination.items, pagination=pagination,
        current_action=action_f, actions=actions,
    )


# ── Admin: statistics ────────────────────────────────────────────────────────
@app.route('/admin/stats')
@admin_required
def admin_stats():
    import json as _json
    from collections import defaultdict

    period    = request.args.get('period', 'month')
    date_from = request.args.get('date_from', '').strip()
    date_to   = request.args.get('date_to', '').strip()
    now_utc   = datetime.utcnow()

    # ── Period boundaries (stored as UTC, displayed as UTC+5) ─────────────────
    if period == 'today':
        # "сегодня" по UTC+5 → сдвигаем на −5ч чтобы получить UTC
        local_today = (now_utc + timedelta(hours=5)).replace(hour=0, minute=0, second=0, microsecond=0)
        start = local_today - timedelta(hours=5)
        end   = now_utc
    elif period == 'yesterday':
        local_yest = (now_utc + timedelta(hours=5) - timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
        start = local_yest - timedelta(hours=5)
        end   = start + timedelta(days=1) - timedelta(seconds=1)
    elif period == 'week':
        start = now_utc - timedelta(days=7)
        end   = now_utc
    elif period == 'month':
        start = now_utc - timedelta(days=30)
        end   = now_utc
    elif period == 'year':
        start = now_utc - timedelta(days=365)
        end   = now_utc
    elif period == 'custom' and date_from:
        try:
            start = datetime.fromisoformat(date_from) - timedelta(hours=5)
            end   = (datetime.fromisoformat(date_to) + timedelta(days=1) - timedelta(seconds=1) - timedelta(hours=5)
                     if date_to else now_utc)
        except ValueError:
            start = now_utc - timedelta(days=30)
            end   = now_utc
    else:  # all
        start = datetime(2020, 1, 1)
        end   = now_utc

    # ── Completed orders in range ─────────────────────────────────────────────
    orders = (
        Order.query
        .filter(Order.status == 'completed',
                Order.created_at >= start,
                Order.created_at <= end)
        .order_by(Order.created_at.asc())
        .all()
    )

    total_revenue  = sum(o.estimated_price or 0 for o in orders)
    total_orders   = len(orders)
    commission_sum = int(total_revenue * COMMISSION_RATE)
    avg_order      = int(total_revenue / total_orders) if total_orders else 0

    cash_rev     = sum(o.estimated_price or 0 for o in orders if o.payment == 'cash')
    transfer_rev = sum(o.estimated_price or 0 for o in orders if o.payment == 'transfer')

    # ── Per-driver breakdown ──────────────────────────────────────────────────
    drv_map = {}
    for o in orders:
        tid = o.driver_telegram_id or '__none__'
        if tid not in drv_map:
            drv_obj = Driver.query.filter_by(telegram_id=tid).first() if tid != '__none__' else None
            drv_map[tid] = {
                'name': o.driver_name or '(не назначен)',
                'orders': 0, 'revenue': 0,
                'balance': drv_obj.balance if drv_obj else 0,
            }
        drv_map[tid]['orders']  += 1
        drv_map[tid]['revenue'] += o.estimated_price or 0

    driver_rows = sorted(drv_map.values(), key=lambda x: x['revenue'], reverse=True)
    for d in driver_rows:
        d['commission'] = int(d['revenue'] * COMMISSION_RATE)
        d['pct']        = round(d['revenue'] / total_revenue * 100) if total_revenue else 0

    # ── Daily chart data (UTC+5 dates) ────────────────────────────────────────
    daily = defaultdict(int)
    daily_orders = defaultdict(int)
    for o in orders:
        day = (o.created_at + timedelta(hours=5)).strftime('%d.%m')
        daily[day]        += o.estimated_price or 0
        daily_orders[day] += 1

    chart_labels   = list(daily.keys())
    chart_revenue  = list(daily.values())
    chart_orders   = [daily_orders[d] for d in chart_labels]

    # ── All-time totals for header cards ─────────────────────────────────────
    all_total = db.session.query(db.func.sum(Order.estimated_price)).filter(
        Order.status == 'completed').scalar() or 0
    all_count = Order.query.filter_by(status == 'completed').count() if False else \
                Order.query.filter(Order.status == 'completed').count()

    return render_template('admin_stats.html',
        period=period, date_from=date_from, date_to=date_to,
        total_revenue=total_revenue, total_orders=total_orders,
        commission_sum=commission_sum, commission_rate=int(COMMISSION_RATE * 100),
        avg_order=avg_order, cash_rev=cash_rev, transfer_rev=transfer_rev,
        driver_rows=driver_rows,
        chart_labels=_json.dumps(chart_labels),
        chart_revenue=_json.dumps(chart_revenue),
        chart_orders=_json.dumps(chart_orders),
        all_total=all_total, all_count=all_count,
    )


# ── Driver join page ──────────────────────────────────────────────────────────
@app.route('/join')
def join():
    return render_template('join.html', owner_phone=OWNER_PHONE, owner_phone_raw=OWNER_PHONE_RAW)


@app.route('/apply', methods=['POST'])
def apply_driver():
    data = request.get_json(silent=True) or {}
    name  = str(data.get('name', '')).strip()
    phone = str(data.get('phone', '')).strip()
    city  = str(data.get('city', '')).strip()
    if not name or not phone or not city:
        return jsonify({'error': 'Заполните обязательные поля'}), 400
    route_type_raw = str(data.get('route_type', '')).strip()
    if route_type_raw not in ('local', 'intercity', 'any'):
        route_type_raw = None
    work_days_list = data.get('work_days', [])
    if isinstance(work_days_list, list):
        work_days_str = ','.join(work_days_list) or None
    else:
        work_days_str = str(work_days_list).strip() or None
    app_obj = DriverApplication(
        name=name, phone=phone, city=city,
        car_model=str(data.get('car_model', '')).strip() or None,
        car_year=str(data.get('car_year', '')).strip() or None,
        car_color=str(data.get('car_color', '')).strip() or None,
        experience=str(data.get('experience', '')).strip() or None,
        telegram=str(data.get('telegram', '')).strip() or None,
        message=str(data.get('message', '')).strip() or None,
        work_from=str(data.get('work_from', '')).strip() or None,
        work_to=str(data.get('work_to', '')).strip() or None,
        work_days=work_days_str,
        route_type=route_type_raw,
    )
    db.session.add(app_obj)
    db.session.commit()
    _log('application_new', actor='site', details=f'{name} · {phone} · {city}')
    _send_push_to_all('🆕 Новая заявка водителя', f'{name} из {city}, тел: {phone}', '/admin/driver-applications')
    return jsonify({'success': True})


# ── Admin: driver applications ────────────────────────────────────────────────
@app.route('/admin/driver-applications')
@admin_required
def admin_driver_applications():
    status_filter = request.args.get('status', 'all')
    q = DriverApplication.query.order_by(DriverApplication.created_at.desc())
    if status_filter != 'all':
        q = q.filter_by(status=status_filter)
    apps = q.all()
    counts = {
        'all':      DriverApplication.query.count(),
        'new':      DriverApplication.query.filter_by(status='new').count(),
        'reviewed': DriverApplication.query.filter_by(status='reviewed').count(),
        'approved': DriverApplication.query.filter_by(status='approved').count(),
        'rejected': DriverApplication.query.filter_by(status='rejected').count(),
    }
    return render_template('admin_driver_applications.html',
                           apps=apps, status_filter=status_filter, counts=counts)


@app.route('/admin/driver-applications/<int:app_id>/status', methods=['POST'])
@admin_required
def update_application_status(app_id):
    app_obj = DriverApplication.query.get_or_404(app_id)
    new_status = request.form.get('status', '')
    if new_status in ('new', 'reviewed', 'approved', 'rejected'):
        app_obj.status = new_status
        db.session.commit()
        _log('application_status', actor='admin', details=f'{app_obj.name} → {new_status}')
    return redirect(url_for('admin_driver_applications', status=request.args.get('status', 'all')))


@app.route('/admin/driver-applications/<int:app_id>/to-driver', methods=['POST'])
@admin_required
def application_to_driver(app_id):
    app_obj = DriverApplication.query.get_or_404(app_id)
    existing = None
    if app_obj.telegram:
        existing = Driver.query.filter_by(telegram_id=app_obj.telegram).first()
    if not existing:
        driver = Driver(
            telegram_id=app_obj.telegram or f'app_{app_obj.id}',
            name=app_obj.name, phone=app_obj.phone,
            car_model=app_obj.car_model, car_color=app_obj.car_color,
        )
        db.session.add(driver)
        app_obj.status = 'approved'
        db.session.commit()
        _log('driver_added', actor='admin', details=f'Из заявки: {app_obj.name}')
    else:
        app_obj.status = 'approved'
        db.session.commit()
    return redirect(url_for('admin_driver_applications'))


@app.route('/admin/driver-applications/<int:app_id>/delete', methods=['POST'])
@admin_required
def delete_application(app_id):
    app_obj = DriverApplication.query.get_or_404(app_id)
    db.session.delete(app_obj)
    db.session.commit()
    return redirect(url_for('admin_driver_applications'))


@app.route('/admin/driver-applications/<int:app_id>/edit', methods=['POST'])
@admin_required
def edit_application(app_id):
    a = DriverApplication.query.get_or_404(app_id)
    a.name       = str(request.form.get('name', a.name)).strip() or a.name
    a.phone      = str(request.form.get('phone', a.phone)).strip() or a.phone
    a.city       = str(request.form.get('city', a.city)).strip() or a.city
    a.car_model  = str(request.form.get('car_model', '')).strip() or None
    a.car_year   = str(request.form.get('car_year', '')).strip() or None
    a.car_color  = str(request.form.get('car_color', '')).strip() or None
    a.experience = str(request.form.get('experience', '')).strip() or None
    a.telegram   = str(request.form.get('telegram', '')).strip() or None
    a.work_from  = str(request.form.get('work_from', '')).strip() or None
    a.work_to    = str(request.form.get('work_to', '')).strip() or None
    days = request.form.getlist('work_days')
    a.work_days  = ','.join(days) if days else None
    rt = str(request.form.get('route_type', '')).strip()
    a.route_type = rt if rt in ('local', 'intercity', 'any') else None
    a.message    = str(request.form.get('message', '')).strip() or None
    db.session.commit()
    _log('application_status', actor='admin', details=f'Заявка #{app_id} отредактирована')
    return redirect(url_for('admin_driver_applications'))


# ── Push notification routes ──────────────────────────────────────────────────
@app.route('/api/push/vapid-public-key')
def push_vapid_public_key():
    return jsonify({'key': VAPID_PUBLIC_KEY, 'enabled': bool(VAPID_PUBLIC_KEY)})


@app.route('/api/push/subscribe', methods=['POST'])
@admin_required
def push_subscribe():
    data = request.get_json(silent=True) or {}
    endpoint = data.get('endpoint', '')
    p256dh   = data.get('keys', {}).get('p256dh', '')
    auth     = data.get('keys', {}).get('auth', '')
    if not endpoint or not p256dh or not auth:
        return jsonify({'error': 'Invalid subscription'}), 400
    existing = PushSubscription.query.filter_by(endpoint=endpoint).first()
    if not existing:
        db.session.add(PushSubscription(endpoint=endpoint, p256dh=p256dh, auth=auth))
        db.session.commit()
    return jsonify({'ok': True})


@app.route('/api/push/unsubscribe', methods=['POST'])
@admin_required
def push_unsubscribe():
    data = request.get_json(silent=True) or {}
    endpoint = data.get('endpoint', '')
    if endpoint:
        PushSubscription.query.filter_by(endpoint=endpoint).delete()
        db.session.commit()
    return jsonify({'ok': True})


# ── Admin: VAPID setup ────────────────────────────────────────────────────────
@app.route('/admin/vapid-setup')
@admin_required
def admin_vapid_setup():
    generated = None
    if request.args.get('generate') == '1':
        try:
            from cryptography.hazmat.primitives.asymmetric import ec
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import serialization
            import base64
            private_key_obj = ec.generate_private_key(ec.SECP256R1(), default_backend())
            pub_bytes = private_key_obj.public_key().public_bytes(
                serialization.Encoding.X962,
                serialization.PublicFormat.UncompressedPoint,
            )
            priv_bytes = private_key_obj.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.TraditionalOpenSSL,
                serialization.NoEncryption(),
            )
            pub_b64  = base64.urlsafe_b64encode(pub_bytes).decode().rstrip('=')
            priv_pem = priv_bytes.decode()
            generated = {'public': pub_b64, 'private': priv_pem}
        except Exception as e:
            generated = {'error': str(e)}
    return render_template('admin_vapid_setup.html',
                           generated=generated,
                           push_enabled=bool(VAPID_PUBLIC_KEY),
                           vapid_public_key=VAPID_PUBLIC_KEY,
                           sub_count=PushSubscription.query.count())


# ── PWA service worker ────────────────────────────────────────────────────────
@app.route('/static/driver-sw.js')
def driver_sw():
    resp = make_response(
        open(os.path.join(app.root_path, 'static', 'driver-sw.js'),
             encoding='utf-8').read()
    )
    resp.headers['Content-Type'] = 'application/javascript; charset=utf-8'
    resp.headers['Service-Worker-Allowed'] = '/driver/'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp


# ── PWA manifest с явной UTF-8 кодировкой ────────────────────────────────────
@app.route('/static/driver-manifest.json')
def driver_manifest():
    resp = make_response(
        open(os.path.join(app.root_path, 'static', 'driver-manifest.json'),
             encoding='utf-8').read()
    )
    resp.headers['Content-Type'] = 'application/manifest+json; charset=utf-8'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp


# ── Digital Asset Links — нужен для TWA/APK от PWABuilder ───────────────────
# Замените fingerprint после того как скачаете APK из PWABuilder
# ── Client PWA manifest & SW ──────────────────────────────────────────────────
@app.route('/static/client-manifest.json')
def client_manifest():
    resp = make_response(
        open(os.path.join(app.root_path, 'static', 'client-manifest.json'),
             encoding='utf-8').read()
    )
    resp.headers['Content-Type'] = 'application/manifest+json; charset=utf-8'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp


@app.route('/static/client-sw.js')
def client_sw():
    resp = make_response(
        open(os.path.join(app.root_path, 'static', 'client-sw.js'),
             encoding='utf-8').read()
    )
    resp.headers['Content-Type'] = 'application/javascript; charset=utf-8'
    resp.headers['Service-Worker-Allowed'] = '/'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp


@app.route('/download/app')
def download_app():
    """Скачать APK клиентского приложения."""
    apk_path = os.path.join(app.root_path, 'static', 'app', 'kazanskoe-taxi.apk')
    if os.path.exists(apk_path):
        return send_file(apk_path, as_attachment=True,
                         download_name='Казанское-Такси.apk',
                         mimetype='application/vnd.android.package-archive')
    return 'APK ещё не загружен', 404


@app.route('/download/driver')
def download_driver_app():
    """Скачать APK приложения водителя."""
    apk_path = os.path.join(app.root_path, 'static', 'app', 'driver-app.apk')
    if os.path.exists(apk_path):
        return send_file(apk_path, as_attachment=True,
                         download_name='Такси-Водитель.apk',
                         mimetype='application/vnd.android.package-archive')
    return 'APK ещё не загружен', 404


# ── Digital Asset Links для обоих приложений ─────────────────────────────────
@app.route('/.well-known/assetlinks.json')
def assetlinks():
    import json as _json
    data = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "app.railway.up.taxi_production_3985.twa",
                "sha256_cert_fingerprints": [
                    "D8:4E:88:24:06:9D:24:FC:43:80:9C:77:2C:63:9D:3D:06:D7:DF:65:A8:0E:7F:1B:68:C0:02:DA:F8:EE:CC:0E"
                ]
            }
        },
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "app.railway.up.taxi_production_3985.twa.app",
                "sha256_cert_fingerprints": [
                    "52:AB:2E:D3:63:BD:B5:F7:A3:DA:D0:A7:C2:18:B1:FB:59:95:DB:AD:D8:4D:4F:61:F0:E3:C0:B2:A9:4A:34:1C"
                ]
            }
        }
    ]
    resp = make_response(_json.dumps(data, ensure_ascii=False))
    resp.headers['Content-Type'] = 'application/json; charset=utf-8'
    resp.headers['Cache-Control'] = 'no-cache'
    return resp


# ── Dispatcher guide ─────────────────────────────────────────────────────────
@app.route('/admin/guide')
@admin_required
def admin_dispatcher_guide():
    return render_template('admin_dispatcher_guide.html')


# ── Driver app ───────────────────────────────────────────────────────────────
def _get_driver_session():
    """Return Driver object for current session or None."""
    driver_id = session.get('driver_id')
    if not driver_id:
        return None
    return Driver.query.get(driver_id)


def driver_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        driver = _get_driver_session()
        if not driver or not driver.active:
            session.pop('driver_id', None)
            return redirect(url_for('driver_login'))
        return f(*args, **kwargs)
    return decorated


@app.route('/driver/')
@app.route('/driver')
@driver_required
def driver_dashboard():
    driver = _get_driver_session()
    if not driver.regulations_accepted:
        return redirect(url_for('driver_regulations'))
    return render_template('driver_dashboard.html', driver=driver)


def _phone_digits(phone):
    """Return last 10 digits of a Russian phone number (strips +7 / 8 prefix)."""
    digits = ''.join(c for c in (phone or '') if c.isdigit())
    if len(digits) == 11 and digits[0] in ('7', '8'):
        return digits[1:]   # strip country/trunk prefix → 10 digits
    return digits


@app.route('/driver/login', methods=['GET', 'POST'])
def driver_login():
    error = None
    if request.method == 'POST':
        phone_in = str(request.form.get('phone', '')).strip()
        pin_in   = str(request.form.get('pin', '')).strip()

        # Collect ALL active drivers matching this phone number
        candidates = []
        if phone_in:
            norm_in = _phone_digits(phone_in)
            for d in Driver.query.filter_by(active=True).all():
                if not d.phone:
                    continue
                if d.phone == phone_in or _phone_digits(d.phone) == norm_in:
                    candidates.append(d)

        if not candidates:
            error = 'Водитель с таким номером не найден'
        else:
            # Find the candidate whose PIN matches
            matched = next((d for d in candidates if d.driver_pin and d.driver_pin.strip() == pin_in.strip()), None)
            if matched:
                session.permanent = True
                session['driver_id'] = matched.id
                if not matched.regulations_accepted:
                    return redirect(url_for('driver_regulations'))
                return redirect(url_for('driver_dashboard'))
            # No PIN match — give a helpful error
            has_any_pin = any(d.driver_pin for d in candidates)
            if not has_any_pin:
                error = 'PIN не задан. Обратитесь к диспетчеру'
            else:
                error = 'Неверный PIN'
    return render_template('driver_login.html', error=error)


@app.route('/driver/logout')
def driver_logout():
    session.pop('driver_id', None)
    return redirect(url_for('driver_login'))


@app.route('/driver/regulations', methods=['GET', 'POST'])
@driver_required
def driver_regulations():
    driver = _get_driver_session()
    if request.method == 'POST':
        driver.regulations_accepted = True
        driver.regulations_accepted_at = datetime.utcnow()
        db.session.commit()
        return redirect(url_for('driver_dashboard'))
    return render_template('driver_regulations.html', driver=driver)


@app.route('/driver/api/orders')
@driver_required
def driver_api_orders():
    """JSON: new orders matching driver's route type."""
    driver = _get_driver_session()
    rt = driver.route_type or 'any'
    all_new = Order.query.filter_by(status='new').order_by(Order.created_at.asc()).all()
    result = []
    for o in all_new:
        is_ic = telegram_bot._is_intercity(o) if hasattr(telegram_bot, '_is_intercity') else False
        if rt == 'local' and is_ic:
            continue
        if rt == 'intercity' and not is_ic:
            continue
        result.append({
            'id': o.id,
            'from_address': o.from_address,
            'to_address': o.to_address,
            'phone': o.phone,
            'payment': 'Наличные' if o.payment == 'cash' else 'Перевод',
            'ride_type': 'Попутчики' if o.ride_type == 'shared' else 'Индивидуально',
            'estimated_price': o.estimated_price,
            'comment': o.comment or '',
            'distance_km': o.distance_km,
            'duration_min': o.duration_min,
            'scheduled_at': (o.scheduled_at + timedelta(hours=5)).strftime('%d.%m %H:%M') if o.scheduled_at else None,
            'created_at': (o.created_at + timedelta(hours=5)).strftime('%H:%M'),
            'intercity': is_ic,
        })
    # current accepted order for this driver
    my_id = driver.telegram_id or f'app:{driver.id}'
    my_order = Order.query.filter(
        Order.driver_telegram_id.in_([driver.telegram_id, f'app:{driver.id}']),
        Order.status == 'accepted',
    ).order_by(Order.created_at.desc()).first() if driver.telegram_id else \
        Order.query.filter_by(driver_telegram_id=f'app:{driver.id}', status='accepted').first()
    my_order_data = None
    if my_order:
        my_order_data = {
            'id': my_order.id,
            'from_address': my_order.from_address,
            'to_address': my_order.to_address,
            'phone': my_order.phone,
            'payment': 'Наличные' if my_order.payment == 'cash' else 'Перевод',
            'estimated_price': my_order.estimated_price,
            'comment': my_order.comment or '',
            'distance_km': my_order.distance_km,
            'duration_min': my_order.duration_min,
            'scheduled_at': (my_order.scheduled_at + timedelta(hours=5)).strftime('%d.%m %H:%M') if my_order.scheduled_at else None,
        }
    # history: last 15 completed orders
    history = Order.query.filter(
        Order.driver_telegram_id.in_([driver.telegram_id, f'app:{driver.id}']) if driver.telegram_id
        else Order.driver_telegram_id == f'app:{driver.id}',
        Order.status == 'completed',
    ).order_by(Order.created_at.desc()).limit(15).all()
    history_data = [{
        'id': o.id,
        'from_address': o.from_address,
        'to_address': o.to_address,
        'estimated_price': o.estimated_price,
        'created_at': (o.created_at + timedelta(hours=5)).strftime('%d.%m %H:%M'),
    } for o in history]
    completed_count = Order.query.filter(
        Order.driver_telegram_id.in_([driver.telegram_id, f'app:{driver.id}']) if driver.telegram_id
        else Order.driver_telegram_id == f'app:{driver.id}',
        Order.status == 'completed',
    ).count()
    # Today in UTC+5
    _now = datetime.utcnow()
    _today_ekb = (_now + timedelta(hours=5)).replace(hour=0, minute=0, second=0, microsecond=0)
    _today_utc = _today_ekb - timedelta(hours=5)
    _my_tids = [driver.telegram_id, f'app:{driver.id}'] if driver.telegram_id else [f'app:{driver.id}']
    today_earnings = db.session.query(db.func.sum(Order.estimated_price)).filter(
        Order.driver_telegram_id.in_(_my_tids),
        Order.status == 'completed',
        Order.created_at >= _today_utc,
    ).scalar() or 0
    _unread_group, _unread_direct = _driver_chat_unread(driver)
    return jsonify({
        'new_orders': result,
        'my_order': my_order_data,
        'history': history_data,
        'balance': driver.balance or 0,
        'completed_count': completed_count,
        'today_earnings': today_earnings,
        'driver_name': driver.name,
        'is_online': bool(driver.is_online),
        'chat_unread_group': _unread_group,
        'chat_unread_direct': _unread_direct,
    })


@app.route('/driver/order/<int:order_id>/accept', methods=['POST'])
@driver_required
def driver_accept_order(order_id):
    driver = _get_driver_session()
    order = Order.query.get_or_404(order_id)
    if order.status != 'new':
        return jsonify({'error': 'Заказ уже принят другим водителем'}), 409
    # Check if driver already has an accepted order
    my_tid = [driver.telegram_id, f'app:{driver.id}'] if driver.telegram_id else [f'app:{driver.id}']
    existing = Order.query.filter(Order.driver_telegram_id.in_(my_tid), Order.status == 'accepted').first()
    if existing:
        return jsonify({'error': 'У вас уже есть активный заказ'}), 409
    tid = driver.telegram_id or f'app:{driver.id}'
    order.status             = 'accepted'
    order.driver_telegram_id = tid
    order.driver_name        = driver.name
    order.reminder_sent      = False
    db.session.commit()
    _log('status_changed', actor=driver.name, order_id=order.id,
         details=f'Принят водителем через приложение')
    return jsonify({'ok': True})


@app.route('/driver/order/<int:order_id>/complete', methods=['POST'])
@driver_required
def driver_complete_order(order_id):
    driver = _get_driver_session()
    order = Order.query.get_or_404(order_id)
    my_tid = [driver.telegram_id, f'app:{driver.id}'] if driver.telegram_id else [f'app:{driver.id}']
    if order.driver_telegram_id not in my_tid:
        return jsonify({'error': 'Это не ваш заказ'}), 403
    if order.status != 'accepted':
        return jsonify({'error': 'Заказ не в статусе "принят"'}), 409
    try:
        actual = int(request.get_json(silent=True).get('actual_price', 0) or 0)
    except Exception:
        actual = 0
    amount = actual or order.estimated_price or 0
    commission = INTERCITY_COMMISSION if telegram_bot._is_intercity(order) else 0
    order.status = 'completed'
    if amount:
        order.estimated_price = amount
        driver.balance = (driver.balance or 0) + amount - commission
    db.session.commit()
    _log('status_changed', actor=driver.name, order_id=order.id,
         details=f'Завершён через приложение. Сумма: {amount} ₽' +
                 (f', комиссия: -{commission} ₽' if commission else ''))
    return jsonify({'ok': True, 'amount': amount, 'commission': commission})


@app.route('/driver/order/<int:order_id>/cancel', methods=['POST'])
@driver_required
def driver_cancel_order(order_id):
    driver = _get_driver_session()
    order = Order.query.get_or_404(order_id)
    my_tid = [driver.telegram_id, f'app:{driver.id}'] if driver.telegram_id else [f'app:{driver.id}']
    if order.driver_telegram_id not in my_tid:
        return jsonify({'error': 'Это не ваш заказ'}), 403
    order.status             = 'new'
    order.driver_telegram_id = None
    order.driver_name        = None
    order.reminder_sent      = False
    db.session.commit()
    _log('status_changed', actor=driver.name, order_id=order.id,
         details='Водитель отменил заказ через приложение')
    try:
        telegram_bot.notify_drivers(order)
    except Exception:
        pass
    return jsonify({'ok': True})


@app.route('/admin/drivers/<int:driver_id>/online', methods=['POST'])
@admin_required
def toggle_driver_online(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    driver.is_online = not driver.is_online
    driver.online_at = datetime.utcnow() if driver.is_online else None
    db.session.commit()
    status = 'в сети' if driver.is_online else 'не в сети'
    _log('driver_updated', actor='admin', details=f'{driver.name} → {status}')
    return redirect(url_for('admin_drivers'))


@app.route('/driver/status', methods=['POST'])
@driver_required
def driver_set_status():
    driver = _get_driver_session()
    online = request.get_json(silent=True).get('online', False)
    driver.is_online = bool(online)
    driver.online_at = datetime.utcnow() if driver.is_online else None
    db.session.commit()
    return jsonify({'ok': True, 'online': driver.is_online})


@app.route('/driver/push/subscribe', methods=['POST'])
@driver_required
def driver_push_subscribe():
    driver = _get_driver_session()
    data = request.get_json(silent=True) or {}
    endpoint = data.get('endpoint', '')
    p256dh   = data.get('keys', {}).get('p256dh', '')
    auth     = data.get('keys', {}).get('auth', '')
    if not endpoint or not p256dh or not auth:
        return jsonify({'ok': False}), 400
    existing = DriverPushSubscription.query.filter_by(endpoint=endpoint).first()
    if existing:
        existing.driver_id = driver.id
        existing.p256dh    = p256dh
        existing.auth      = auth
    else:
        db.session.add(DriverPushSubscription(
            driver_id=driver.id, endpoint=endpoint, p256dh=p256dh, auth=auth
        ))
    db.session.commit()
    return jsonify({'ok': True})


@app.route('/driver/push/unsubscribe', methods=['POST'])
@driver_required
def driver_push_unsubscribe():
    data = request.get_json(silent=True) or {}
    endpoint = data.get('endpoint', '')
    if endpoint:
        DriverPushSubscription.query.filter_by(endpoint=endpoint).delete()
        db.session.commit()
    return jsonify({'ok': True})


# ── Приложение водителя: чат ──────────────────────────────────────────────────
@app.route('/driver/api/chat')
@driver_required
def driver_chat_fetch():
    driver = _get_driver_session()
    which  = request.args.get('room', 'group')
    after  = request.args.get('after', 0, type=int)
    room = 'group' if which == 'group' else f'd{driver.id}'
    msgs = (ChatMessage.query
            .filter(ChatMessage.room == room, ChatMessage.id > after)
            .order_by(ChatMessage.id.asc()).limit(200).all())
    return jsonify({'messages': [_msg_dict(m) for m in msgs], 'me': driver.id})


@app.route('/driver/api/chat/send', methods=['POST'])
@driver_required
def driver_chat_send():
    driver = _get_driver_session()
    data = request.get_json(silent=True) or {}
    which = str(data.get('room', 'group')).strip()
    body  = str(data.get('body', '')).strip()
    if not body:
        return jsonify({'error': 'Пустое сообщение'}), 400
    if len(body) > 2000:
        body = body[:2000]
    room = 'group' if which == 'group' else f'd{driver.id}'

    m = ChatMessage(room=room, sender='driver', driver_id=driver.id,
                    author_name=driver.name, body=body, read_admin=False)
    db.session.add(m)
    db.session.commit()

    # Push диспетчеру (+ другим водителям в общем чате)
    try:
        if room == 'group':
            _send_push_to_all(f'💬 {driver.name}', body[:120], '/admin/chat')
            for other in Driver.query.filter(Driver.active == True, Driver.id != driver.id).all():
                _send_push_to_one_driver(other.id, f'💬 {driver.name} (общий)', body[:120], '/driver/?tab=chat')
        else:
            _send_push_to_all(f'💬 {driver.name}', body[:120], '/admin/chat')
    except Exception as _e:
        print(f'[CHAT-PUSH] {_e}')

    return jsonify({'ok': True, 'message': _msg_dict(m)})


@app.route('/driver/api/chat/seen', methods=['POST'])
@driver_required
def driver_chat_seen():
    driver = _get_driver_session()
    which = str((request.get_json(silent=True) or {}).get('room', 'group')).strip()
    now = datetime.utcnow()
    if which == 'group':
        driver.chat_seen_group = now
    else:
        driver.chat_seen_direct = now
    db.session.commit()
    return jsonify({'ok': True})


@app.route('/driver/push/test', methods=['POST'])
@driver_required
def driver_push_test():
    """Самопроверка фонового push: реально шлёт push водителю и возвращает,
    сколько подписок, сколько доставлено push-сервису и текст ошибок."""
    driver = _get_driver_session()
    vapid_ok = bool(VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY)
    subs = DriverPushSubscription.query.filter_by(driver_id=driver.id).all()
    sent, dead, errors = 0, [], []
    if vapid_ok and subs:
        try:
            from pywebpush import webpush
            payload = _json_mod.dumps({
                'title': '✅ Тест уведомления',
                'body':  'Видите это при закрытом приложении? Значит фоновые уведомления работают!',
                'url':   '/driver/',
            })
            for sub in subs:
                try:
                    webpush(
                        subscription_info={'endpoint': sub.endpoint,
                                           'keys': {'p256dh': sub.p256dh, 'auth': sub.auth}},
                        data=payload,
                        vapid_private_key=VAPID_PRIVATE_KEY,
                        vapid_claims={'sub': VAPID_EMAIL},
                    )
                    sent += 1
                except Exception as _pe:
                    msg = str(_pe)
                    errors.append(msg[:180])
                    if '410' in msg or '404' in msg:
                        dead.append(sub.id)
            for did in dead:
                DriverPushSubscription.query.filter_by(id=did).delete()
            if dead:
                db.session.commit()
        except ImportError:
            errors.append('pywebpush не установлен на сервере')
    uniq = []
    for e in errors:
        if e not in uniq:
            uniq.append(e)
    return jsonify({
        'ok': True, 'vapid': vapid_ok,
        'subs': len(subs), 'sent': sent,
        'removed': len(dead), 'email': VAPID_EMAIL,
        'errors': uniq[:3],
    })


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
