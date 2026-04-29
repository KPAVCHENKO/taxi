"""
MAX Messenger Bot (ICQ Bot API compatible)
API docs: https://dev.icq.net/botapi/
Endpoint: https://api.icq.net/bot/v1
"""
import os
import json
import requests


def _token():
    return os.environ.get('MAX_BOT_TOKEN', '')


def _post(method, params=None, json_body=None):
    token = _token()
    if not token:
        print('[MAX] MAX_BOT_TOKEN not set — skipping')
        return {}
    url = f'https://api.icq.net/bot/v1/{method}'
    try:
        if json_body is not None:
            r = requests.post(url, params={'token': token}, json=json_body, timeout=10)
        else:
            p = dict(params or {})
            p['token'] = token
            r = requests.get(url, params=p, timeout=10)
        return r.json()
    except Exception as exc:
        print(f'[MAX] {method} error: {exc}')
        return {}


def send_message(chat_id, text, inline_keyboard=None):
    """Send text message. inline_keyboard is list of lists of {'text','callbackData'}."""
    params = {'chatId': str(chat_id), 'text': text}
    if inline_keyboard:
        params['inlineKeyboardMarkup'] = json.dumps(inline_keyboard)
    return _post('messages/sendText', params=params)


def edit_message(chat_id, msg_id, text):
    params = {'chatId': str(chat_id), 'msgId': str(msg_id), 'text': text}
    return _post('messages/editText', params=params)


def answer_callback(query_id, text=''):
    params = {'queryId': str(query_id), 'text': text}
    return _post('events/answerCallbackQuery', params=params)


def notify_drivers(order):
    """Send new order notification to MAX-enabled drivers."""
    from models import Driver, db

    drivers = Driver.query.filter(
        Driver.active == True,
        Driver.messenger.in_(['max', 'both']),
        Driver.max_id.isnot(None),
    ).all()
    if not drivers:
        return

    from datetime import timedelta
    import math as _math

    def _hav(lat1, lon1, lat2, lon2):
        R, d = 6371, _math.radians
        a = _math.sin((d(lat2)-d(lat1))/2)**2 + _math.cos(d(lat1))*_math.cos(d(lat2))*_math.sin((d(lon2)-d(lon1))/2)**2
        return R * 2 * _math.asin(_math.sqrt(a))

    sched = ''
    if order.scheduled_at:
        _t = order.scheduled_at + timedelta(hours=5)
        sched = f'\n🕐 Время: {_t.strftime("%d.%m.%Y %H:%M")}'

    route_info = ''
    try:
        if order.from_lat and order.from_lon and order.to_lat and order.to_lon:
            km = round(_hav(order.from_lat, order.from_lon, order.to_lat, order.to_lon) * 1.25)
            mins = km  # at 60 km/h: minutes == km
            route_info = f'\n📏 Расстояние: ~{km} км · ~{mins} мин'
    except Exception:
        pass

    _comment = getattr(order, 'comment', None)
    comment_line = f'\n💬 Комментарий: {_comment}' if _comment and str(_comment).strip() not in ('', 'None') else ''
    pay_label  = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'
    ride_raw   = getattr(order, 'ride_type', 'individual') or 'individual'
    ride_label = '👥 Попутно (дешевле)' if ride_raw == 'shared' else '🚗 Индивидуально'
    _ep        = getattr(order, 'estimated_price', None)
    price_line = f'💰 Цена: {_ep:,} ₽'.replace(',', ' ') if _ep else '💰 Цена уточняется диспетчером'

    text = (
        f'🚖 Новый заказ #{order.id}\n\n'
        f'📍 Откуда: {order.from_address}\n'
        f'🏁 Куда: {order.to_address}'
        f'{route_info}{comment_line}{sched}\n\n'
        f'🎫 Тип: {ride_label}\n'
        f'💳 Оплата: {pay_label}\n'
        f'{price_line}\n'
        f'📞 Телефон скрыт до принятия'
    )

    keyboard = [[
        {'text': '✅ Принять', 'callbackData': f'accept:{order.id}'},
        {'text': '❌ Пропустить', 'callbackData': f'skip:{order.id}'},
    ]]

    msg_ids = {}
    try:
        existing = json.loads(order.message_ids or '{}')
    except (json.JSONDecodeError, TypeError):
        existing = {}

    for driver in drivers:
        result = send_message(driver.max_id, text, keyboard)
        mid = (result.get('msgId') or
               (result.get('result') or {}).get('msgId'))
        if mid:
            msg_ids[f'max:{driver.max_id}'] = mid

    existing.update(msg_ids)
    order.message_ids = json.dumps(existing)
    db.session.commit()


def handle_update(update):
    """Handle incoming MAX webhook event."""
    from models import db, Order, Driver as _Driver, DispatchLog

    events = update.get('events', [])
    for event in events:
        if event.get('type') != 'callbackQuery':
            continue

        payload     = event.get('payload', {})
        query_id    = payload.get('queryId', '')
        cb_data     = payload.get('callbackData', '')
        from_info   = payload.get('from', {})
        user_id     = str(from_info.get('userId', ''))
        user_name   = from_info.get('firstName', '') + ' ' + from_info.get('lastName', '')
        user_name   = user_name.strip()
        chat_id     = payload.get('chat', {}).get('chatId', user_id)
        msg_id      = payload.get('message', {}).get('msgId', '')

        if ':' not in cb_data:
            continue
        action, oid_str = cb_data.split(':', 1)
        try:
            order_id = int(oid_str)
        except ValueError:
            continue

        order = Order.query.get(order_id)
        if not order:
            answer_callback(query_id, '⚠️ Заказ не найден')
            continue

        if action == 'skip':
            answer_callback(query_id, 'Вы пропустили заказ')
            continue

        if action == 'complete':
            if order.driver_telegram_id != f'max:{user_id}':
                answer_callback(query_id, '⚠️ Этот заказ не ваш')
                continue
            if order.status != 'accepted':
                answer_callback(query_id, '⚠️ Заказ уже не активен')
                continue
            order.status = 'completed'
            amount = getattr(order, 'estimated_price', None) or 0
            if amount > 0:
                driver_obj2 = _Driver.query.filter_by(max_id=user_id).first()
                if driver_obj2:
                    driver_obj2.balance = (driver_obj2.balance or 0) + amount
            db.session.commit()
            try:
                db.session.add(DispatchLog(
                    action='driver_completed', actor=user_name,
                    order_id=order.id,
                    details=f'Водитель {user_name} отметил заказ выполненным (MAX)'
                ))
                db.session.commit()
            except Exception:
                db.session.rollback()
            answer_callback(query_id, '✅ Заказ завершён! Спасибо.')
            edit_message(chat_id, msg_id, f'✅ Заказ #{order.id} — ЗАВЕРШЁН\n\n📍 {order.from_address}\n🏁 {order.to_address}\n\nСпасибо за поездку! 🙏')
            continue

        if action == 'cancel':
            # Find driver by max_id
            driver_obj = _Driver.query.filter_by(max_id=user_id).first()
            if not driver_obj or order.driver_telegram_id != f'max:{user_id}':
                answer_callback(query_id, '⚠️ Этот заказ не ваш')
                continue
            if order.status != 'accepted':
                answer_callback(query_id, '⚠️ Заказ уже не активен')
                continue

            order.status             = 'new'
            order.driver_telegram_id = None
            order.driver_name        = None
            db.session.commit()

            try:
                db.session.add(DispatchLog(
                    action='driver_cancelled', actor=user_name,
                    order_id=order.id,
                    details=f'Водитель {user_name} отменил заказ (MAX)'
                ))
                db.session.commit()
            except Exception:
                db.session.rollback()

            answer_callback(query_id, '↩ Заказ отменён, вернулся в очередь')
            # Re-notify
            import telegram_bot
            telegram_bot.notify_drivers(order)
            notify_drivers(order)
            continue

        if action == 'accept':
            if order.status != 'new':
                answer_callback(query_id, '❌ Заказ уже взят другим водителем')
                continue

            # Mark driver_telegram_id with max: prefix so system knows it's MAX driver
            order.status             = 'accepted'
            order.driver_telegram_id = f'max:{user_id}'
            order.driver_name        = user_name
            db.session.commit()

            try:
                db.session.add(DispatchLog(
                    action='driver_accepted', actor=user_name,
                    order_id=order.id,
                    details=f'Водитель {user_name} принял заказ (MAX)'
                ))
                db.session.commit()
            except Exception:
                db.session.rollback()

            answer_callback(query_id, '✅ Заказ принят! Телефон клиента показан ниже.')

            pay_label = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'
            _ep2      = getattr(order, 'estimated_price', None)
            price_line2 = f'💰 Цена: {_ep2:,} ₽'.replace(',', ' ') if _ep2 else '💰 Цена уточняется'

            driver_obj = _Driver.query.filter_by(max_id=user_id).first()
            car_line = f'\n🚗 Ваш автомобиль: {driver_obj.car_info}' if (driver_obj and driver_obj.car_info) else ''

            accepted_text = (
                f'✅ Заказ #{order.id} — ПРИНЯТ ВАМИ\n\n'
                f'📍 Откуда: {order.from_address}\n'
                f'🏁 Куда: {order.to_address}\n\n'
                f'💳 Оплата: {pay_label}\n'
                f'{price_line2}\n'
                f'📞 Телефон клиента: {order.phone}'
                f'{car_line}'
            )

            cancel_keyboard = [
                [{'text': '✅ Завершил заказ', 'callbackData': f'complete:{order.id}'}],
                [{'text': '❌ Отменить заказ', 'callbackData': f'cancel:{order.id}'}],
            ]
            send_message(chat_id, accepted_text, cancel_keyboard)

            # Notify other drivers that order is taken
            if order.message_ids:
                try:
                    msg_ids = json.loads(order.message_ids)
                except (json.JSONDecodeError, TypeError):
                    msg_ids = {}

                taken_text = f'🚫 Заказ #{order.id} уже принят другим водителем'
                for tid, mid in msg_ids.items():
                    if tid.startswith('max:') and tid != f'max:{user_id}':
                        edit_message(tid[4:], mid, taken_text)
