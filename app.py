import os
from datetime import datetime, timedelta
from functools import wraps

from flask import (
    Flask, render_template, request, jsonify,
    session, redirect, url_for, flash,
)

from sqlalchemy import text
from models import db, Order, Driver, Review
import telegram_bot

app = Flask(__name__)

# ── Config ────────────────────────────────────────────────────────────────────
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'change-me-in-production-please')

_db_url = os.environ.get('DATABASE_URL', 'sqlite:///taxi.db')
# Railway may give postgres:// — SQLAlchemy needs postgresql+psycopg2://
if _db_url.startswith('postgres://'):
    _db_url = _db_url.replace('postgres://', 'postgresql+psycopg2://', 1)
elif _db_url.startswith('postgresql://'):
    _db_url = _db_url.replace('postgresql://', 'postgresql+psycopg2://', 1)

app.config['SQLALCHEMY_DATABASE_URI'] = _db_url
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

ADMIN_PASSWORD    = os.environ.get('ADMIN_PASSWORD', 'admin123')
YANDEX_MAPS_KEY   = os.environ.get('YANDEX_MAPS_KEY', '')

# ── Реквизиты владельца (заполните в переменных окружения или здесь) ──────────
OWNER_NAME    = os.environ.get('OWNER_NAME',    'ИП Иванов Иван Иванович')
OWNER_OGRN    = os.environ.get('OWNER_OGRN',    '000000000000000')
OWNER_INN     = os.environ.get('OWNER_INN',     '000000000000')
OWNER_ADDRESS = os.environ.get('OWNER_ADDRESS', 'Тюменская область, Казанский район, с. Казанское')
OWNER_PHONE   = os.environ.get('OWNER_PHONE',   '+7 (963) 060-84-19')
OWNER_PHONE_RAW = os.environ.get('OWNER_PHONE_RAW', '+79630608419')
OWNER_EMAIL   = os.environ.get('OWNER_EMAIL',   'info@example.ru')
SITE_URL      = os.environ.get('SITE_URL',      'https://kazanskoe-taxi.ru')

def legal_ctx():
    """Общий контекст для юридических страниц."""
    return dict(
        owner_name=OWNER_NAME,
        owner_ogrn=OWNER_OGRN,
        owner_inn=OWNER_INN,
        owner_address=OWNER_ADDRESS,
        owner_phone=OWNER_PHONE,
        owner_phone_raw=OWNER_PHONE_RAW,
        owner_email=OWNER_EMAIL,
        site_url=SITE_URL,
    )

db.init_app(app)

with app.app_context():
    db.create_all()
    # ── Миграция: добавляем колонки, которых может не быть в старой БД ──
    _migrations = [
        "ALTER TABLE orders ADD COLUMN comment TEXT",
        "ALTER TABLE orders ADD COLUMN payment VARCHAR(20) DEFAULT 'cash'",
        "ALTER TABLE orders ADD COLUMN from_lat FLOAT",
        "ALTER TABLE orders ADD COLUMN from_lon FLOAT",
        "ALTER TABLE orders ADD COLUMN to_lat FLOAT",
        "ALTER TABLE orders ADD COLUMN to_lon FLOAT",
        "ALTER TABLE orders ADD COLUMN ride_type VARCHAR(20) DEFAULT 'individual'",
        "ALTER TABLE orders ADD COLUMN estimated_price INTEGER",
        "ALTER TABLE drivers ADD COLUMN car_model VARCHAR(100)",
        "ALTER TABLE drivers ADD COLUMN car_color VARCHAR(50)",
        "ALTER TABLE drivers ADD COLUMN car_plate VARCHAR(20)",
    ]
    with db.engine.connect() as _conn:
        for _sql in _migrations:
            try:
                _conn.execute(text(_sql))
                _conn.commit()
            except Exception:
                pass  # колонка уже существует — игнорируем


# ── Jinja фильтр: UTC → UTC+5 (Екатеринбург) ─────────────────────────────────
@app.template_filter('ekb')
def ekb_time(dt):
    """Конвертирует UTC datetime в строку UTC+5 для отображения."""
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


# ── Public routes ─────────────────────────────────────────────────────────────
@app.route('/')
def index():
    reviews = (
        Review.query
        .filter_by(approved=True)
        .order_by(Review.created_at.desc())
        .limit(12)
        .all()
    )
    return render_template('index.html', reviews=reviews, yandex_maps_key=YANDEX_MAPS_KEY)


@app.route('/order', methods=['POST'])
def create_order():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'Нет данных'}), 400

    phone        = str(data.get('phone', '')).strip()
    from_address = str(data.get('from_address', '')).strip()
    to_address   = str(data.get('to_address', '')).strip()
    # comment может прийти как null из JSON → None → str(None)='None' — баг
    _comment_raw = data.get('comment')
    comment      = str(_comment_raw).strip() if _comment_raw else ''
    payment_raw   = str(data.get('payment', 'cash')).strip()
    payment       = 'transfer' if payment_raw == 'transfer' else 'cash'
    ride_type_raw = str(data.get('ride_type', 'individual')).strip()
    ride_type     = 'shared' if ride_type_raw == 'shared' else 'individual'

    # estimated_price — int или None (вычисляется на клиенте по таблице цен)
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

    # Координаты необязательны — водитель поймёт по адресу + комментарию
    def _float_or_none(key):
        v = data.get(key)
        try:
            return float(v) if v not in (None, '', 'null') else None
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
        phone=phone,
        from_address=from_address,
        from_lat=_float_or_none('from_lat'),
        from_lon=_float_or_none('from_lon'),
        to_address=to_address,
        to_lat=_float_or_none('to_lat'),
        to_lon=_float_or_none('to_lon'),
        comment=comment or None,
        payment=payment,
        ride_type=ride_type,
        estimated_price=estimated_price,
        scheduled_at=scheduled_at,
    )
    db.session.add(order)
    db.session.commit()

    telegram_bot.notify_drivers(order)

    return jsonify({'success': True, 'order_id': order.id})


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

    db.session.add(Review(name=name, text=text))
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


# ── Admin: dashboard ─────────────────────────────────────────────────────────
@app.route('/admin')
@app.route('/admin/dashboard')
@admin_required
def admin_dashboard():
    from datetime import date
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    total_new       = Order.query.filter_by(status='new').count()
    total_accepted  = Order.query.filter_by(status='accepted').count()
    today_all       = Order.query.filter(Order.created_at >= today_start).count()
    today_completed = Order.query.filter(
        Order.created_at >= today_start, Order.status == 'completed'
    ).count()
    today_accepted  = Order.query.filter(
        Order.created_at >= today_start, Order.status != 'new'
    ).count()

    active_drivers = Driver.query.filter_by(active=True).count()

    conversion = round(today_accepted / today_all * 100) if today_all else 0

    recent_orders = (
        Order.query.filter_by(status='new')
        .order_by(Order.created_at.desc())
        .limit(5).all()
    )

    return render_template('admin_dashboard.html',
        total_new=total_new,
        total_accepted=total_accepted,
        today_all=today_all,
        today_completed=today_completed,
        active_drivers=active_drivers,
        conversion=conversion,
        recent_orders=recent_orders,
    )


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

    # Railway (and most PaaS) terminate SSL at the load balancer,
    # so request.host_url returns http:// — force https://
    host = request.host_url.rstrip('/')
    host = host.replace('http://', 'https://', 1)
    webhook_url = f"{host}/webhook/{tg_token}"
    resp = req.post(
        f'https://api.telegram.org/bot{tg_token}/setWebhook',
        json={'url': webhook_url},
        timeout=10,
    )
    return jsonify({'webhook_url': webhook_url, 'telegram_response': resp.json()})


# ── Статус занятости водителей ────────────────────────────────────────────────
def compute_driver_statuses(drivers):
    """
    Возвращает dict {driver.id: {'label': str, 'level': 'free'|'maybe'|'busy'}}.
    Расчёт по последнему принятому заказу.
    """
    from datetime import datetime
    result = {}
    for d in drivers:
        # Активный незавершённый заказ
        active = (
            Order.query
            .filter_by(driver_telegram_id=d.telegram_id, status='accepted')
            .order_by(Order.created_at.desc())
            .first()
        )
        if active:
            # Заказ на будущее — водитель сейчас свободен
            if active.scheduled_at and active.scheduled_at > datetime.utcnow() + timedelta(hours=1):
                result[d.id] = {'label': 'Свободен', 'level': 'free'}
                continue
            mins = int((datetime.utcnow() - active.created_at).total_seconds() / 60)
            if mins < 90:
                result[d.id] = {'label': f'Выполняет заказ · {mins} мин', 'level': 'busy'}
            else:
                result[d.id] = {'label': f'Возможно занят · {mins} мин', 'level': 'maybe'}
            continue

        # Недавно завершённый (< 20 мин назад)
        recent = (
            Order.query
            .filter_by(driver_telegram_id=d.telegram_id, status='completed')
            .order_by(Order.created_at.desc())
            .first()
        )
        if recent:
            mins = int((datetime.utcnow() - recent.created_at).total_seconds() / 60)
            if mins < 20:
                result[d.id] = {'label': f'Только завершил · {mins} мин назад', 'level': 'maybe'}
                continue

        result[d.id] = {'label': 'Свободен', 'level': 'free'}
    return result


# ── Admin: orders ─────────────────────────────────────────────────────────────
@app.route('/admin/orders')
@admin_required
def admin_orders():
    status = request.args.get('status', '')
    q = Order.query
    if status:
        q = q.filter_by(status=status)
    orders  = q.order_by(Order.created_at.desc()).all()
    drivers = Driver.query.filter_by(active=True).order_by(Driver.name).all()
    driver_statuses = compute_driver_statuses(drivers)
    return render_template('admin_orders.html', orders=orders,
                           current_status=status, drivers=drivers,
                           driver_statuses=driver_statuses)


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
            telegram_bot.notify_driver_assigned(order, driver)
    return redirect(url_for('admin_orders', status=request.args.get('status', '')))


@app.route('/admin/orders/<int:order_id>/status', methods=['POST'])
@admin_required
def update_order_status(order_id):
    order = Order.query.get_or_404(order_id)
    new_status = request.form.get('status', '')
    if new_status in ('new', 'accepted', 'completed'):
        order.status = new_status
        db.session.commit()
    return redirect(url_for('admin_orders', status=request.args.get('status', '')))


# ── Admin: dispatcher PWA ────────────────────────────────────────────────────
@app.route('/admin/dispatcher')
@admin_required
def admin_dispatcher():
    return render_template('admin_dispatcher.html')


@app.route('/api/dispatcher')
@admin_required
def api_dispatcher():
    """JSON API для PWA-диспетчера — polling каждые 15 сек."""
    from datetime import date as _date

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

    return jsonify({
        'orders_new':       [order_dict(o) for o in Order.query.filter_by(status='new').order_by(Order.created_at.desc()).all()],
        'orders_accepted':  [order_dict(o) for o in Order.query.filter_by(status='accepted').order_by(Order.created_at.desc()).all()],
        'orders_completed': [order_dict(o) for o in Order.query.filter_by(status='completed').order_by(Order.created_at.desc()).limit(20).all()],
        'drivers':          [{'id': d.id, 'name': d.name, 'telegram_id': d.telegram_id,
                               'car_info': d.car_info or ''} for d in drivers],
        'driver_statuses':  {str(k): v for k, v in statuses.items()},
        'today_count':      Order.query.filter(Order.created_at >= today_start).count(),
        'active_drivers':   len(drivers),
    })


# ── Admin: reviews ────────────────────────────────────────────────────────────
@app.route('/admin/reviews')
@admin_required
def admin_reviews():
    reviews = Review.query.order_by(Review.approved.asc(), Review.created_at.desc()).all()
    return render_template('admin_reviews.html', reviews=reviews)


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
    return render_template('admin_drivers.html', drivers=drivers)


@app.route('/admin/drivers/add', methods=['POST'])
@admin_required
def add_driver():
    tid       = str(request.form.get('telegram_id', '')).strip()
    name      = str(request.form.get('name', '')).strip()
    car_model = str(request.form.get('car_model', '')).strip() or None
    car_color = str(request.form.get('car_color', '')).strip() or None
    car_plate = str(request.form.get('car_plate', '')).strip() or None
    if tid and name:
        if not Driver.query.filter_by(telegram_id=tid).first():
            db.session.add(Driver(
                telegram_id=tid, name=name,
                car_model=car_model, car_color=car_color, car_plate=car_plate,
            ))
            db.session.commit()
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/edit', methods=['POST'])
@admin_required
def edit_driver(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    name      = str(request.form.get('name', '')).strip()
    car_model = str(request.form.get('car_model', '')).strip() or None
    car_color = str(request.form.get('car_color', '')).strip() or None
    car_plate = str(request.form.get('car_plate', '')).strip() or None
    if name:
        driver.name = name
    driver.car_model = car_model
    driver.car_color = car_color
    driver.car_plate = car_plate
    db.session.commit()
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/toggle', methods=['POST'])
@admin_required
def toggle_driver(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    driver.active = not driver.active
    db.session.commit()
    return redirect(url_for('admin_drivers'))


@app.route('/admin/drivers/<int:driver_id>/delete', methods=['POST'])
@admin_required
def delete_driver(driver_id):
    driver = Driver.query.get_or_404(driver_id)
    db.session.delete(driver)
    db.session.commit()
    return redirect(url_for('admin_drivers'))


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False)
