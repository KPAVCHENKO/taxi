import os
import json
import math
import requests


def _haversine_km(lat1, lon1, lat2, lon2):
    """Straight-line distance between two coordinates in km."""
    R = 6371
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = math.sin(d_lat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lon/2)**2
    return R * 2 * math.asin(math.sqrt(a))


def _route_info(order):
    """Return route line from stored data or fallback haversine."""
    # Используем точные данные если сохранены с фронтенда (Yandex Routes)
    km   = getattr(order, 'distance_km', None)
    mins = getattr(order, 'duration_min', None)
    if km and mins:
        return f'\n📏 <b>Расстояние:</b> ~{round(km)} км · ~{mins} мин'
    # Фолбек — Haversine
    try:
        if order.from_lat and order.from_lon and order.to_lat and order.to_lon:
            km_h = _haversine_km(order.from_lat, order.from_lon, order.to_lat, order.to_lon)
            km_road = round(km_h * 1.25)
            mins_h  = km_road
            return f'\n📏 <b>Расстояние:</b> ~{km_road} км · ~{mins_h} мин'
    except Exception:
        pass
    return ''


def _token():
    return os.environ.get('TELEGRAM_TOKEN', '')


def _post(method, payload):
    token = _token()
    if not token:
        print('[TG] TELEGRAM_TOKEN not set — skipping')
        return {}
    try:
        r = requests.post(
            f'https://api.telegram.org/bot{token}/{method}',
            json=payload, timeout=10,
        )
        return r.json()
    except Exception as exc:
        print(f'[TG] {method} error: {exc}')
        return {}


def send_message(chat_id, text, reply_markup=None):
    payload = {'chat_id': chat_id, 'text': text, 'parse_mode': 'HTML'}
    if reply_markup:
        payload['reply_markup'] = reply_markup
    return _post('sendMessage', payload)


def edit_message_text(chat_id, message_id, text, reply_markup=None):
    payload = {
        'chat_id': chat_id, 'message_id': message_id,
        'text': text, 'parse_mode': 'HTML',
    }
    if reply_markup:
        payload['reply_markup'] = reply_markup
    return _post('editMessageText', payload)


def answer_callback_query(callback_query_id, text='', show_alert=False):
    return _post('answerCallbackQuery', {
        'callback_query_id': callback_query_id,
        'text': text, 'show_alert': show_alert,
    })


def _is_intercity(order):
    """Определяет, является ли заказ межгородским по адресу."""
    _intercity_keys = ['ишим', 'петропавловск']
    text = ((order.to_address or '') + ' ' + (order.from_address or '')).lower()
    return any(k in text for k in _intercity_keys)


def notify_drivers(order):
    """Send new order notification to matching active drivers (filtered by route_type)."""
    from models import Driver, db

    intercity = _is_intercity(order)
    all_drivers = Driver.query.filter(
        Driver.active == True,
        Driver.messenger.in_(['telegram', 'both']),
    ).all()

    # Фильтруем по route_type: intercity-водители не получают местные заказы и наоборот
    drivers = []
    for d in all_drivers:
        rt = d.route_type or 'any'
        if intercity and rt == 'local':
            continue
        if not intercity and rt == 'intercity':
            continue
        drivers.append(d)

    if not drivers:
        print('[TG] No matching drivers to notify')
        return

    sched = ''
    if order.scheduled_at:
        from datetime import timedelta
        _t = order.scheduled_at + timedelta(hours=5)
        sched = f'\n🕐 <b>Время:</b> {_t.strftime("%d.%m.%Y %H:%M")}'

    _comment     = getattr(order, 'comment', None)
    comment_line = (f'\n💬 <b>Комментарий:</b> {_comment}'
                    if _comment and str(_comment).strip() not in ('', 'None') else '')
    coords_note  = '' if (order.from_lat and order.to_lat) else '\n⚠️ Координаты не указаны'
    pay_label    = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'
    ride_raw     = getattr(order, 'ride_type', 'individual') or 'individual'
    ride_label   = '👥 Попутно (дешевле)' if ride_raw == 'shared' else '🚗 Индивидуально'
    ride_note    = '\n⚡️ <b>Можно взять попутчиков!</b>' if ride_raw == 'shared' else ''

    _ep = getattr(order, 'estimated_price', None)
    if _ep:
        price_line = f'💰 <b>Цена:</b> {_ep:,} ₽'.replace(',', ' ')
        if ride_raw == 'shared':
            price_line += ' (попутно — дешевле)'
    else:
        price_line = '💰 Цена уточняется диспетчером'

    route_info = _route_info(order)
    text = (
        f'🚖 <b>Новый заказ #{order.id}</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{route_info}{comment_line}{sched}{coords_note}\n\n'
        f'🎫 <b>Тип:</b> {ride_label}{ride_note}\n'
        f'💳 <b>Оплата:</b> {pay_label}\n'
        f'{price_line}\n'
        f'📞 Телефон скрыт до принятия'
    )

    markup = {
        'inline_keyboard': [[
            {'text': '✅ Принять', 'callback_data': f'accept:{order.id}'},
            {'text': '❌ Пропустить', 'callback_data': f'skip:{order.id}'},
        ]]
    }

    msg_ids = {}
    for driver in drivers:
        result = send_message(driver.telegram_id, text, markup)
        if result.get('ok'):
            msg_ids[str(driver.telegram_id)] = result['result']['message_id']

    order.message_ids = json.dumps(msg_ids)
    db.session.commit()


def notify_driver_assigned(order, driver):
    """Уведомить водителя о ручном назначении диспетчером."""
    sched = ''
    if order.scheduled_at:
        from datetime import timedelta
        _t2 = order.scheduled_at + timedelta(hours=5)
        sched = f'\n🕐 <b>Время:</b> {_t2.strftime("%d.%m.%Y %H:%M")}'

    _c3 = getattr(order, 'comment', None)
    comment_line = (f'\n💬 <b>Комментарий:</b> {_c3}'
                    if _c3 and str(_c3).strip() not in ('', 'None') else '')
    _ep3 = getattr(order, 'estimated_price', None)
    price_line3  = (f'\n💰 <b>Цена:</b> {_ep3:,} ₽'.replace(',', ' ') if _ep3 else '')
    pay_label3   = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'

    markup = {
        'inline_keyboard': [
            [{'text': '✅ Завершил заказ', 'callback_data': f'complete:{order.id}'}],
            [{'text': '❌ Отменить заказ', 'callback_data': f'cancel:{order.id}'}],
        ]
    }

    route_info3 = _route_info(order)
    text = (
        f'📋 <b>Заказ #{order.id} — назначен диспетчером</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{route_info3}{comment_line}{sched}\n\n'
        f'💳 <b>Оплата:</b> {pay_label3}'
        f'{price_line3}\n'
        f'📞 <b>Телефон клиента:</b> <code>{order.phone}</code>'
    )
    send_message(driver.telegram_id, text, markup)


def send_scheduled_reminder(order):
    """Напоминание водителю за ~1.5 часа до планового заказа."""
    from datetime import timedelta
    _t = (order.scheduled_at + timedelta(hours=5)).strftime('%d.%m.%Y %H:%M')
    text = (
        f'⏰ <b>Напоминание о заказе #{order.id}</b>\n\n'
        f'📍 {order.from_address}\n'
        f'🏁 {order.to_address}\n'
        f'🕐 Время поездки: <b>{_t}</b>\n\n'
        f'Всё в силе?'
    )
    markup = {'inline_keyboard': [[
        {'text': '✅ Да, еду', 'callback_data': f'remind_ok:{order.id}'},
        {'text': '❌ Не смогу', 'callback_data': f'remind_no:{order.id}'},
    ]]}
    send_message(order.driver_telegram_id, text, markup)


# ── Пассажирский заказ через бота ─────────────────────────────────────────────
_PRICE_LOCAL = {
    'казанское': 150, 'новоселезнево': 200, 'шадринка': 300, 'яровское': 300,
    'большие ярки': 300, 'малые ярки': 400, 'гагарье': 500, 'сладчанка': 500,
    'боровлянка': 600, 'дальнетравное': 600, 'ильинка': 700, 'кугаево': 700,
    'чирки': 700, 'огнево': 800, 'дубынка': 900, 'заречка': 900, 'смирное': 900,
    'афонькино': 1000, 'пешнево': 1000, 'копотилово': 1000, 'ченчерь': 1000,
    'ельцово': 1000, 'коротаевка': 1100, 'грачи': 1200, 'паленка': 1200,
    'новогеоргиевка': 1500, 'новоалександровка': 1500, 'челюскинцев': 1500,
    'викторовка': 1800, 'долматово': 1800,
}
_PRICE_IC = {'ишим': 2000, 'петропавловск': 5000}
_HUB = 'казанское'
_SETTLE = [
    ('казанское', 'Казанское'), ('новоселезнево', 'Новоселезнёво'), ('шадринка', 'Шадринка'),
    ('яровское', 'Яровское'), ('большие ярки', 'Большие Ярки'), ('малые ярки', 'Малые Ярки'),
    ('гагарье', 'Гагарье'), ('сладчанка', 'Сладчанка'), ('боровлянка', 'Боровлянка'),
    ('дальнетравное', 'Дальнетравное'), ('ильинка', 'Ильинка'), ('кугаево', 'Кугаево'),
    ('чирки', 'Чирки'), ('огнево', 'Огнёво'), ('дубынка', 'Дубынка'), ('заречка', 'Заречка'),
    ('смирное', 'Смирное'), ('афонькино', 'Афонькино'), ('пешнево', 'Пешнёво'),
    ('копотилово', 'Копотилово'), ('ченчерь', 'Ченчерь'), ('ельцово', 'Ельцово'),
    ('коротаевка', 'Коротаевка'), ('грачи', 'Грачи'), ('паленка', 'Палёнка'),
    ('новогеоргиевка', 'Новогеоргиевка'), ('новоалександровка', 'Новоалександровка'),
    ('челюскинцев', 'Челюскинцев'), ('викторовка', 'Викторовка'), ('долматово', 'Долматово'),
    ('ишим', 'Ишим (межгород)'), ('петропавловск', 'Петропавловск (межгород)'),
]
_pending = {}  # chat_id -> {'from':key, 'to':key}

def _settle_label(key):
    for k, l in _SETTLE:
        if k == key:
            return l
    return key or ''

def _calc_price(fk, tk):
    if not fk or not tk:
        return None
    if fk in _PRICE_IC:
        return _PRICE_IC[fk]
    if tk in _PRICE_IC:
        return _PRICE_IC[tk]
    if fk == _HUB:
        dest = tk
    elif tk == _HUB:
        dest = fk
    else:
        return None
    return _PRICE_LOCAL.get(dest)

def _settle_kb(prefix):
    rows, row = [], []
    for key, label in _SETTLE:
        row.append({'text': label, 'callback_data': f'{prefix}{key}'})
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    return {'inline_keyboard': rows}


def handle_update(update):
    """Process incoming Telegram update (webhook)."""
    from models import db, Order, Driver as _Driver, DispatchLog

    # ── Текстовые команды (/start, /balance) ─────────────────────────────────
    message = update.get('message')
    if message:
        chat_id  = str(message.get('chat', {}).get('id', ''))
        # Пассажир прислал контакт — создаём заказ
        contact = message.get('contact')
        if contact and chat_id in _pending and _pending[chat_id].get('to'):
            st = _pending.pop(chat_id)
            phone = contact.get('phone_number', '')
            fk, tk = st.get('from'), st.get('to')
            import secrets as _sec
            o = Order(phone=phone, from_address=_settle_label(fk), to_address=_settle_label(tk),
                      payment='cash', ride_type='individual',
                      estimated_price=_calc_price(fk, tk), status='new',
                      cancel_token=_sec.token_urlsafe(16))
            db.session.add(o)
            db.session.commit()
            try:
                notify_drivers(o)
            except Exception:
                pass
            price = _calc_price(fk, tk)
            ptxt = f'\n💰 Стоимость: <b>{price} ₽</b>' if price else '\n💰 Цену уточнит диспетчер'
            send_message(chat_id,
                f'✅ <b>Заказ принят!</b>\n📍 {_settle_label(fk)} → 🏁 {_settle_label(tk)}{ptxt}\n\n'
                'Диспетчер свяжется с вами. Спасибо!',
                {'remove_keyboard': True})
            return
        msg_text = (message.get('text', '') or '').strip().lower()
        if msg_text.startswith('/start') or msg_text.startswith('/balance') or msg_text.startswith('/баланс'):
            driver = _Driver.query.filter_by(telegram_id=chat_id).first()
            if driver:
                from datetime import datetime, timedelta
                balance = driver.balance or 0
                done    = Order.query.filter_by(driver_telegram_id=chat_id, status='completed').count()
                _now = datetime.utcnow()
                _today_start = (_now + timedelta(hours=5)).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(hours=5)
                today_rev = db.session.query(
                    db.func.sum(Order.estimated_price)
                ).filter(
                    Order.driver_telegram_id == chat_id,
                    Order.status == 'completed',
                    Order.created_at >= _today_start,
                ).scalar() or 0
                send_message(chat_id,
                    f'👋 <b>{driver.name}</b>\n\n'
                    f'📅 Сегодня: <b>{today_rev:,} ₽</b>\n'.replace(',', ' ') +
                    f'💰 Баланс: <b>{balance:,} ₽</b>\n'.replace(',', ' ') +
                    f'✅ Выполнено заказов: <b>{done}</b>\n\n'
                    f'Для вопросов обращайтесь к диспетчеру.'
                )
            else:
                send_message(chat_id,
                    '🚕 <b>Казанское Такси</b>\n\n'
                    'Закажите такси прямо здесь: выберите откуда и куда, оставьте номер — '
                    'диспетчер свяжется с вами.',
                    {'inline_keyboard': [[{'text': '🚕 Заказать такси', 'callback_data': 'c_order'}]]})
        return

    callback = update.get('callback_query')
    if not callback:
        return

    cq_id = callback['id']
    data  = callback.get('data', '')
    tg_user    = callback.get('from', {})
    driver_tid = str(tg_user.get('id', ''))
    driver_name = (
        tg_user.get('first_name', '') + ' ' + tg_user.get('last_name', '')
    ).strip()

    msg          = callback.get('message', {})
    msg_chat_id  = str(msg.get('chat', {}).get('id', ''))
    msg_id       = msg.get('message_id')

    # ── Пассажирский заказ ────────────────────────────────────────────────────
    if data == 'c_order':
        answer_callback_query(cq_id)
        send_message(msg_chat_id, '📍 <b>Откуда едем?</b>', _settle_kb('c_from:'))
        return
    if data.startswith('c_from:'):
        _pending.setdefault(msg_chat_id, {})['from'] = data.split(':', 1)[1]
        answer_callback_query(cq_id)
        send_message(msg_chat_id, '🏁 <b>Куда едем?</b>', _settle_kb('c_to:'))
        return
    if data.startswith('c_to:'):
        st = _pending.setdefault(msg_chat_id, {})
        st['to'] = data.split(':', 1)[1]
        answer_callback_query(cq_id)
        _pr = _calc_price(st.get('from'), st.get('to'))
        _ptxt = f'\n💰 Стоимость: <b>{_pr} ₽</b>' if _pr else '\n💰 Цену уточнит диспетчер'
        send_message(msg_chat_id,
            f'📍 {_settle_label(st.get("from"))} → 🏁 {_settle_label(st.get("to"))}{_ptxt}\n\n'
            'Нажмите кнопку, чтобы отправить номер телефона 👇',
            {'keyboard': [[{'text': '📱 Отправить мой номер', 'request_contact': True}]],
             'resize_keyboard': True, 'one_time_keyboard': True})
        return

    if ':' not in data:
        return

    action, oid_str = data.split(':', 1)
    try:
        order_id = int(oid_str)
    except ValueError:
        return

    order = Order.query.get(order_id)
    if not order:
        answer_callback_query(cq_id, '⚠️ Заказ не найден', show_alert=True)
        return

    # ── Reminder confirm/decline ──────────────────────────────────────────────
    if action == 'remind_ok':
        answer_callback_query(cq_id, '✅ Принято, ждём вас!')
        if msg_id:
            from datetime import timedelta
            _t = (order.scheduled_at + timedelta(hours=5)).strftime('%d.%m %H:%M') if order.scheduled_at else '—'
            edit_message_text(msg_chat_id, msg_id,
                f'✅ <b>Заказ #{order.id} — подтверждён</b>\n\n'
                f'📍 {order.from_address}\n🏁 {order.to_address}\n🕐 {_t}'
            )
        return

    if action == 'remind_no':
        # Водитель отказывается от планового заказа — возвращаем в очередь
        if order.status == 'accepted' and order.driver_telegram_id == driver_tid:
            order.status = 'new'
            order.driver_telegram_id = None
            order.driver_name = None
            db.session.commit()
            try:
                db.session.add(DispatchLog(action='driver_cancelled', actor=driver_name,
                    order_id=order.id,
                    details=f'{driver_name} отказался от планового заказа'))
                db.session.commit()
            except Exception:
                db.session.rollback()
            answer_callback_query(cq_id, '↩ Заказ возвращён диспетчеру', show_alert=True)
            if msg_id:
                edit_message_text(msg_chat_id, msg_id,
                    f'❌ <b>Заказ #{order.id}</b> — вы отказались.\nЗаказ вернулся диспетчеру.')
            notify_drivers(order)
        else:
            answer_callback_query(cq_id, 'Заказ уже не активен')
        return

    # ── Skip ──────────────────────────────────────────────────────────────────
    if action == 'skip':
        answer_callback_query(cq_id, 'Вы пропустили заказ')
        return

    # ── Cancel (driver cancels an already-accepted order) ─────────────────────
    if action == 'cancel':
        if order.driver_telegram_id != driver_tid:
            answer_callback_query(cq_id, '⚠️ Этот заказ не ваш', show_alert=True)
            return
        if order.status != 'accepted':
            answer_callback_query(cq_id, '⚠️ Заказ уже не активен', show_alert=True)
            return

        order.status             = 'new'
        order.driver_telegram_id = None
        order.driver_name        = None
        db.session.commit()

        # Log cancellation
        try:
            db.session.add(DispatchLog(
                action='driver_cancelled', actor=driver_name,
                order_id=order.id,
                details=f'Водитель {driver_name} отменил заказ'
            ))
            db.session.commit()
        except Exception:
            db.session.rollback()

        answer_callback_query(cq_id, '↩ Заказ отменён. Он вернулся в очередь.')
        if msg_id:
            edit_message_text(
                msg_chat_id, msg_id,
                f'↩ <b>Заказ #{order.id}</b> — вы отменили. Заказ снова в очереди.'
            )

        # Re-notify all active drivers
        notify_drivers(order)
        return

    # ── Complete (driver marks order done) ────────────────────────────────────
    if action == 'complete':
        if order.driver_telegram_id != driver_tid:
            answer_callback_query(cq_id, '⚠️ Этот заказ не ваш', show_alert=True)
            return
        if order.status != 'accepted':
            answer_callback_query(cq_id, '⚠️ Заказ уже не активен', show_alert=True)
            return

        order.status = 'completed'
        amount = getattr(order, 'estimated_price', None) or 0
        if amount > 0:
            from models import Driver as _DrvModel
            _d = _DrvModel.query.filter_by(telegram_id=driver_tid).first()
            if _d:
                _d.balance = (_d.balance or 0) + amount
        db.session.commit()

        try:
            db.session.add(DispatchLog(
                action='driver_completed', actor=driver_name,
                order_id=order.id,
                details=f'Водитель {driver_name} отметил заказ выполненным'
            ))
            db.session.commit()
        except Exception:
            db.session.rollback()

        answer_callback_query(cq_id, '✅ Заказ завершён! Спасибо.')
        if msg_id:
            edit_message_text(
                msg_chat_id, msg_id,
                f'✅ <b>Заказ #{order.id} — ЗАВЕРШЁН</b>\n\n'
                f'📍 {order.from_address}\n'
                f'🏁 {order.to_address}\n\n'
                f'Спасибо за поездку! 🙏'
            )
        return

    # ── Accept ────────────────────────────────────────────────────────────────
    if action != 'accept':
        return

    if order.status != 'new':
        answer_callback_query(cq_id, '❌ Заказ уже взят другим водителем', show_alert=True)
        if msg_id:
            edit_message_text(
                msg_chat_id, msg_id,
                f'🚫 <b>Заказ #{order.id}</b> уже принят другим водителем'
            )
        return

    order.status             = 'accepted'
    order.driver_telegram_id = driver_tid
    order.driver_name        = driver_name
    db.session.commit()

    # Log acceptance
    try:
        db.session.add(DispatchLog(
            action='driver_accepted', actor=driver_name,
            order_id=order.id,
            details=f'Водитель {driver_name} принял заказ'
        ))
        db.session.commit()
    except Exception:
        db.session.rollback()

    answer_callback_query(cq_id, '✅ Заказ принят! Телефон клиента показан ниже.')

    sched = ''
    if order.scheduled_at:
        from datetime import timedelta
        _t3 = order.scheduled_at + timedelta(hours=5)
        sched = f'\n🕐 <b>Время:</b> {_t3.strftime("%d.%m.%Y %H:%M")}'

    _comment2    = getattr(order, 'comment', None)
    comment_line = (f'\n💬 <b>Комментарий:</b> {_comment2}'
                    if _comment2 and str(_comment2).strip() not in ('', 'None') else '')
    pay_label    = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'
    ride_raw2    = getattr(order, 'ride_type', 'individual') or 'individual'
    ride_label2  = '👥 Попутно' if ride_raw2 == 'shared' else '🚗 Индивидуально'
    _ep2         = getattr(order, 'estimated_price', None)
    price_line2  = (f'💰 <b>Цена:</b> {_ep2:,} ₽'.replace(',', ' ')
                    if _ep2 else '💰 Цена уточняется диспетчером')

    _drv = _Driver.query.filter_by(telegram_id=order.driver_telegram_id).first()
    car_line = ''
    if _drv and _drv.car_info:
        car_line = f'\n\n🚗 <b>Сообщите клиенту:</b>\n<code>{_drv.car_info}</code>'

    accepted_text = (
        f'✅ <b>Заказ #{order.id} — ПРИНЯТ ВАМИ</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{comment_line}{sched}\n\n'
        f'🎫 <b>Тип:</b> {ride_label2}\n'
        f'💳 <b>Оплата:</b> {pay_label}\n'
        f'{price_line2}\n'
        f'📞 <b>Телефон клиента:</b> <code>{order.phone}</code>'
        f'{car_line}'
    )

    cancel_markup = {
        'inline_keyboard': [
            [{'text': '✅ Завершил заказ', 'callback_data': f'complete:{order.id}'}],
            [{'text': '❌ Отменить заказ', 'callback_data': f'cancel:{order.id}'}],
        ]
    }

    if msg_id:
        edit_message_text(msg_chat_id, msg_id, accepted_text, cancel_markup)

    # Notify other drivers
    if order.message_ids:
        try:
            msg_ids = json.loads(order.message_ids)
        except (json.JSONDecodeError, TypeError):
            msg_ids = {}

        taken_text = f'🚫 <b>Заказ #{order.id}</b> уже принят другим водителем'
        for tid, mid in msg_ids.items():
            if tid != driver_tid:
                edit_message_text(tid, mid, taken_text)
