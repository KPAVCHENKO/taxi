from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()


class Order(db.Model):
    __tablename__ = 'orders'

    id                 = db.Column(db.Integer, primary_key=True)
    phone              = db.Column(db.String(20),  nullable=False)
    from_address       = db.Column(db.String(500), nullable=False)
    from_lat           = db.Column(db.Float,        nullable=True)
    from_lon           = db.Column(db.Float,        nullable=True)
    to_address         = db.Column(db.String(500),  nullable=False)
    to_lat             = db.Column(db.Float,        nullable=True)
    to_lon             = db.Column(db.Float,        nullable=True)
    comment            = db.Column(db.Text,         nullable=True)
    payment            = db.Column(db.String(20),   default='cash')   # cash | transfer
    ride_type          = db.Column(db.String(20),   default='individual')  # individual | shared
    estimated_price    = db.Column(db.Integer,      nullable=True)
    scheduled_at       = db.Column(db.DateTime,     nullable=True)
    status             = db.Column(db.String(20),   default='new')    # new | accepted | completed | cancelled
    cancel_token       = db.Column(db.String(40),   nullable=True)    # для отмены заказа клиентом без аккаунта
    driver_telegram_id = db.Column(db.String(50),   nullable=True)
    driver_name        = db.Column(db.String(100),  nullable=True)
    message_ids        = db.Column(db.Text,         nullable=True)    # JSON {telegram_id: message_id}
    distance_km        = db.Column(db.Float,        nullable=True)    # road distance in km
    duration_min       = db.Column(db.Integer,      nullable=True)    # estimated travel time in min
    reminder_sent      = db.Column(db.Boolean,      default=False)    # scheduled reminder sent
    created_at         = db.Column(db.DateTime,     default=datetime.utcnow)

    @property
    def status_label(self):
        return {'new': 'Новый', 'accepted': 'Принят', 'completed': 'Завершён',
                'cancelled': 'Отменён'}.get(self.status, self.status)

    @property
    def has_coords(self):
        return bool(self.from_lat) and bool(self.from_lon)


class Driver(db.Model):
    __tablename__ = 'drivers'

    id          = db.Column(db.Integer, primary_key=True)
    telegram_id = db.Column(db.String(50), unique=True, nullable=False)
    name        = db.Column(db.String(100), nullable=False)
    phone       = db.Column(db.String(20),  nullable=True)   # телефон для диспетчера
    car_model   = db.Column(db.String(100), nullable=True)
    car_color   = db.Column(db.String(50),  nullable=True)
    car_plate   = db.Column(db.String(20),  nullable=True)
    active      = db.Column(db.Boolean, default=True)
    balance     = db.Column(db.Integer, default=0)
    # График и маршруты
    work_from   = db.Column(db.String(10),  nullable=True)
    work_to     = db.Column(db.String(10),  nullable=True)
    work_days   = db.Column(db.String(100), nullable=True)
    route_type  = db.Column(db.String(20),  nullable=True)  # local | intercity | any
    # Мессенджеры
    max_id           = db.Column(db.String(100), nullable=True)  # ID в MAX
    messenger        = db.Column(db.String(20),  default='telegram')  # telegram | max | both
    telegram_username = db.Column(db.String(100), nullable=True)  # @username в Telegram
    driver_pin       = db.Column(db.String(20),  nullable=True)
    regulations_accepted    = db.Column(db.Boolean,  default=False)
    regulations_accepted_at = db.Column(db.DateTime, nullable=True)
    is_online        = db.Column(db.Boolean, default=False)   # в сети прямо сейчас
    online_at        = db.Column(db.DateTime, nullable=True)  # когда вышел на смену
    chat_seen_group  = db.Column(db.DateTime, nullable=True)  # когда последний раз открывал общий чат
    chat_seen_direct = db.Column(db.DateTime, nullable=True)  # когда последний раз открывал чат с диспетчером

    @property
    def car_info(self):
        parts = [p for p in [self.car_color, self.car_model, self.car_plate] if p]
        return ' · '.join(parts) if parts else None


class Tariff(db.Model):
    __tablename__ = 'tariffs'

    id               = db.Column(db.Integer, primary_key=True)
    destination      = db.Column(db.String(100), nullable=False, unique=True)  # lowercase key
    price            = db.Column(db.Integer, nullable=False)                   # one-way price
    round_trip_price = db.Column(db.Integer, nullable=True)                    # for intercity
    intercity        = db.Column(db.Boolean, default=False)
    active           = db.Column(db.Boolean, default=True)


class DispatchLog(db.Model):
    __tablename__ = 'dispatch_log'

    id         = db.Column(db.Integer, primary_key=True)
    action     = db.Column(db.String(50),  nullable=False)
    actor      = db.Column(db.String(100), nullable=True)
    order_id   = db.Column(db.Integer,     nullable=True)
    details    = db.Column(db.Text,        nullable=True)
    created_at = db.Column(db.DateTime,    default=datetime.utcnow)


class Review(db.Model):
    __tablename__ = 'reviews'

    id         = db.Column(db.Integer, primary_key=True)
    name       = db.Column(db.String(100), nullable=False)
    text       = db.Column(db.Text,        nullable=False)
    approved   = db.Column(db.Boolean,     default=False)
    type       = db.Column(db.String(20),  default='review')  # review | wish
    created_at = db.Column(db.DateTime,    default=datetime.utcnow)


class Setting(db.Model):
    __tablename__ = 'settings'

    key   = db.Column(db.String(60), primary_key=True)
    value = db.Column(db.Text)


class ChatMessage(db.Model):
    __tablename__ = 'chat_messages'

    id          = db.Column(db.Integer, primary_key=True)
    room        = db.Column(db.String(40), nullable=False, index=True)  # 'group' | 'd<driver_id>'
    sender      = db.Column(db.String(10), nullable=False)              # 'admin' | 'driver'
    driver_id   = db.Column(db.Integer, nullable=True)                  # автор (если driver) / собеседник
    author_name = db.Column(db.String(100), nullable=True)
    body        = db.Column(db.Text, nullable=False)
    read_admin  = db.Column(db.Boolean, default=False)                  # диспетчер прочитал сообщение водителя
    created_at  = db.Column(db.DateTime, default=datetime.utcnow, index=True)


class DriverApplication(db.Model):
    __tablename__ = 'driver_applications'

    id         = db.Column(db.Integer, primary_key=True)
    name       = db.Column(db.String(100), nullable=False)
    phone      = db.Column(db.String(20),  nullable=False)
    city       = db.Column(db.String(100), nullable=False)
    car_model  = db.Column(db.String(100), nullable=True)
    car_year   = db.Column(db.String(10),  nullable=True)
    car_color  = db.Column(db.String(50),  nullable=True)
    experience = db.Column(db.String(30),  nullable=True)
    telegram   = db.Column(db.String(100), nullable=True)
    message    = db.Column(db.Text,        nullable=True)
    work_from  = db.Column(db.String(10),  nullable=True)   # "08:00"
    work_to    = db.Column(db.String(10),  nullable=True)   # "22:00"
    work_days  = db.Column(db.String(100), nullable=True)   # "пн,вт,ср,чт,пт"
    route_type = db.Column(db.String(20),  nullable=True)   # local | intercity | any
    status     = db.Column(db.String(20),  default='new')   # new/reviewed/approved/rejected
    created_at = db.Column(db.DateTime,    default=datetime.utcnow)


class PushSubscription(db.Model):
    __tablename__ = 'push_subscriptions'

    id         = db.Column(db.Integer, primary_key=True)
    endpoint   = db.Column(db.Text,    unique=True, nullable=False)
    p256dh     = db.Column(db.Text,    nullable=False)
    auth       = db.Column(db.Text,    nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)


class DriverPushSubscription(db.Model):
    __tablename__ = 'driver_push_subscriptions'

    id         = db.Column(db.Integer, primary_key=True)
    driver_id  = db.Column(db.Integer, nullable=False)
    endpoint   = db.Column(db.Text,    unique=True, nullable=False)
    p256dh     = db.Column(db.Text,    nullable=False)
    auth       = db.Column(db.Text,    nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
