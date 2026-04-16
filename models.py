from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()


class Order(db.Model):
    __tablename__ = 'orders'

    id                 = db.Column(db.Integer, primary_key=True)
    phone              = db.Column(db.String(20),  nullable=False)
    from_address       = db.Column(db.String(500), nullable=False)
    from_lat           = db.Column(db.Float,        nullable=True)   # может быть null если нет GPS
    from_lon           = db.Column(db.Float,        nullable=True)
    to_address         = db.Column(db.String(500),  nullable=False)
    to_lat             = db.Column(db.Float,        nullable=True)
    to_lon             = db.Column(db.Float,        nullable=True)
    comment            = db.Column(db.Text,         nullable=True)   # уточнение адреса / доп. инфо
    payment            = db.Column(db.String(20),   default='cash')  # cash | transfer
    scheduled_at       = db.Column(db.DateTime,     nullable=True)
    status             = db.Column(db.String(20),   default='new')   # new | accepted | completed
    driver_telegram_id = db.Column(db.String(50),   nullable=True)
    driver_name        = db.Column(db.String(100),  nullable=True)
    message_ids        = db.Column(db.Text,         nullable=True)   # JSON {telegram_id: message_id}
    created_at         = db.Column(db.DateTime,     default=datetime.utcnow)

    @property
    def status_label(self):
        return {'new': 'Новый', 'accepted': 'Принят', 'completed': 'Завершён'}.get(
            self.status, self.status)

    @property
    def has_coords(self):
        return self.from_lat is not None and self.from_lon is not None


class Driver(db.Model):
    __tablename__ = 'drivers'

    id          = db.Column(db.Integer, primary_key=True)
    telegram_id = db.Column(db.String(50), unique=True, nullable=False)
    name        = db.Column(db.String(100), nullable=False)
    active      = db.Column(db.Boolean, default=True)


class Review(db.Model):
    __tablename__ = 'reviews'

    id         = db.Column(db.Integer, primary_key=True)
    name       = db.Column(db.String(100), nullable=False)
    text       = db.Column(db.Text,        nullable=False)
    approved   = db.Column(db.Boolean,     default=False)
    created_at = db.Column(db.DateTime,    default=datetime.utcnow)
