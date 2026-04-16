import os
from datetime import datetime
from functools import wraps

from flask import (
    Flask, render_template, request, jsonify,
    session, redirect, url_for, flash,
)

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

ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'admin123')
GEOAPIFY_KEY = os.environ.get('GEOAPIFY_KEY', '39ae8aed8df9420383c9f699413a7b73')

db.init_app(app)

with app.app_context():
    db.create_all()


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
    return render_template('index.html', reviews=reviews, geoapify_key=GEOAPIFY_KEY)


@app.route('/order', methods=['POST'])
def create_order():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({'error': 'Нет данных'}), 400

    required = ['phone', 'from_address', 'from_lat', 'from_lon',
                'to_address', 'to_lat', 'to_lon']
    for field in required:
        if not str(data.get(field, '')).strip():
            return jsonify({'error': f'Поле обязательно: {field}'}), 400

    scheduled_at = None
    raw_dt = data.get('scheduled_at', '')
    if raw_dt:
        try:
            scheduled_at = datetime.fromisoformat(raw_dt)
        except (ValueError, TypeError):
            pass

    order = Order(
        phone=str(data['phone']).strip(),
        from_address=str(data['from_address']).strip(),
        from_lat=float(data['from_lat']),
        from_lon=float(data['from_lon']),
        to_address=str(data['to_address']).strip(),
        to_lat=float(data['to_lat']),
        to_lon=float(data['to_lon']),
        scheduled_at=scheduled_at,
    )
    db.session.add(order)
    db.session.commit()

    telegram_bot.notify_drivers(order)

    return jsonify({'success': True, 'order_id': order.id})


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


# ── Admin: auth ───────────────────────────────────────────────────────────────
@app.route('/a', methods=['GET', 'POST'])
def admin_login():
    if session.get('admin'):
        return redirect(url_for('admin_orders'))

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

    webhook_url = f"{request.host_url.rstrip('/')}/webhook/{tg_token}"
    resp = req.post(
        f'https://api.telegram.org/bot{tg_token}/setWebhook',
        json={'url': webhook_url},
        timeout=10,
    )
    return jsonify({'webhook_url': webhook_url, 'telegram_response': resp.json()})


# ── Admin: orders ─────────────────────────────────────────────────────────────
@app.route('/admin/orders')
@admin_required
def admin_orders():
    status = request.args.get('status', '')
    q = Order.query
    if status:
        q = q.filter_by(status=status)
    orders = q.order_by(Order.created_at.desc()).all()
    return render_template('admin_orders.html', orders=orders, current_status=status)


@app.route('/admin/orders/<int:order_id>/status', methods=['POST'])
@admin_required
def update_order_status(order_id):
    order = Order.query.get_or_404(order_id)
    new_status = request.form.get('status', '')
    if new_status in ('new', 'accepted', 'completed'):
        order.status = new_status
        db.session.commit()
    return redirect(url_for('admin_orders', status=request.args.get('status', '')))


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
    tid = str(request.form.get('telegram_id', '')).strip()
    name = str(request.form.get('name', '')).strip()
    if tid and name:
        if not Driver.query.filter_by(telegram_id=tid).first():
            db.session.add(Driver(telegram_id=tid, name=name))
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
