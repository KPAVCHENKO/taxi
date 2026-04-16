import os
import json
import requests


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
            json=payload,
            timeout=10,
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


def edit_message_text(chat_id, message_id, text):
    return _post('editMessageText', {
        'chat_id': chat_id,
        'message_id': message_id,
        'text': text,
        'parse_mode': 'HTML',
    })


def answer_callback_query(callback_query_id, text='', show_alert=False):
    return _post('answerCallbackQuery', {
        'callback_query_id': callback_query_id,
        'text': text,
        'show_alert': show_alert,
    })


def notify_drivers(order):
    """Send new order notification to all active drivers."""
    from models import Driver, db  # lazy import — requires app context

    drivers = Driver.query.filter_by(active=True).all()
    if not drivers:
        print('[TG] No active drivers to notify')
        return

    sched = ''
    if order.scheduled_at:
        sched = f'\n🕐 <b>Время (UTC+5):</b> {order.scheduled_at.strftime("%d.%m.%Y %H:%M")}'

    comment_line = f'\n💬 <b>Комментарий:</b> {order.comment}' if order.comment else ''
    coords_note  = '' if (order.from_lat and order.to_lat) else '\n⚠️ Координаты не указаны'
    pay_label    = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'

    text = (
        f'🚖 <b>Новый заказ #{order.id}</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{comment_line}'
        f'{sched}'
        f'{coords_note}\n\n'
        f'💳 <b>Оплата:</b> {pay_label}\n'
        f'💰 Цена уточняется диспетчером\n'
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
        ekb = order.scheduled_at + timedelta(hours=5)
        sched = f'\n🕐 <b>Время (UTC+5):</b> {ekb.strftime("%d.%m.%Y %H:%M")}'

    comment_line = f'\n💬 <b>Комментарий:</b> {order.comment}' if order.comment else ''

    text = (
        f'📋 <b>Заказ #{order.id} — назначен диспетчером</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{comment_line}'
        f'{sched}\n\n'
        f'📞 <b>Телефон клиента:</b> <code>{order.phone}</code>'
    )
    send_message(driver.telegram_id, text)


def handle_update(update):
    """Process incoming Telegram update (webhook)."""
    from models import db, Order  # lazy import — requires app context

    callback = update.get('callback_query')
    if not callback:
        return

    cq_id = callback['id']
    data = callback.get('data', '')
    tg_user = callback.get('from', {})
    driver_tid = str(tg_user.get('id', ''))
    driver_name = (
        tg_user.get('first_name', '') + ' ' + tg_user.get('last_name', '')
    ).strip()

    msg = callback.get('message', {})
    msg_chat_id = str(msg.get('chat', {}).get('id', ''))
    msg_id = msg.get('message_id')

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

    if action == 'skip':
        answer_callback_query(cq_id, 'Вы пропустили заказ')
        return

    if action != 'accept':
        return

    # --- Accept order ---
    if order.status != 'new':
        answer_callback_query(cq_id, '❌ Заказ уже взят другим водителем', show_alert=True)
        if msg_id:
            edit_message_text(
                msg_chat_id, msg_id,
                f'🚫 <b>Заказ #{order.id}</b> уже принят другим водителем'
            )
        return

    order.status = 'accepted'
    order.driver_telegram_id = driver_tid
    order.driver_name = driver_name
    db.session.commit()

    answer_callback_query(cq_id, '✅ Заказ принят! Телефон клиента показан ниже.')

    # Show phone number to accepting driver
    sched = ''
    if order.scheduled_at:
        sched = f'\n🕐 <b>Время (UTC+5):</b> {order.scheduled_at.strftime("%d.%m.%Y %H:%M")}'

    comment_line = f'\n💬 <b>Комментарий:</b> {order.comment}' if order.comment else ''
    pay_label    = '💵 Наличные' if getattr(order, 'payment', 'cash') == 'cash' else '📲 Перевод'

    accepted_text = (
        f'✅ <b>Заказ #{order.id} — ПРИНЯТ ВАМИ</b>\n\n'
        f'📍 <b>Откуда:</b> {order.from_address}\n'
        f'🏁 <b>Куда:</b> {order.to_address}'
        f'{comment_line}'
        f'{sched}\n\n'
        f'💳 <b>Оплата:</b> {pay_label}\n'
        f'📞 <b>Телефон клиента:</b> <code>{order.phone}</code>'
    )
    if msg_id:
        edit_message_text(msg_chat_id, msg_id, accepted_text)

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
