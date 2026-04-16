# Деплой на Railway — пошаговая инструкция

## 1. Подготовка

### Создать Telegram бота
1. Открыть @BotFather в Telegram
2. Отправить `/newbot`, задать имя и username
3. Скопировать токен вида `123456789:ABCdef...`

### Получить Telegram ID водителей
1. Каждый водитель пишет боту @userinfobot команду `/start`
2. Бот ответит числовым ID — его нужно добавить в админке

---

## 2. Railway — деплой

### Способ А — через GitHub (рекомендуется)

1. Создать репозиторий на GitHub, загрузить проект
2. Зайти на **railway.app** → New Project → Deploy from GitHub repo
3. Выбрать репозиторий
4. Railway автоматически обнаружит Procfile и запустит

### Способ Б — через CLI

```bash
npm install -g @railway/cli
railway login
railway init
railway up
```

---

## 3. Переменные окружения на Railway

В Railway: Settings → Variables → Add Variable

| Переменная       | Значение                          |
|-----------------|-----------------------------------|
| `SECRET_KEY`    | Случайная строка 50+ символов     |
| `ADMIN_PASSWORD`| Пароль для входа в /a             |
| `TELEGRAM_TOKEN`| Токен от BotFather                |
| `GEOAPIFY_KEY`  | 39ae8aed8df9420383c9f699413a7b73  |
| `PORT`          | Railway ставит автоматически      |

> SQLite работает из коробки. Данные сбрасываются при каждом деплое.
> Для сохранения данных добавьте PostgreSQL плагин в Railway —
> переменная `DATABASE_URL` подставится автоматически.

---

## 4. Настройка Telegram Webhook

После деплоя (когда приложение запущено):

1. Зайти в браузере: `https://ВАШ_ДОМЕН.railway.app/a`
2. Войти в админку
3. В левом меню нажать **Webhook**
4. Откроется JSON с ответом Telegram: `{"ok": true, ...}`

Webhook установлен — бот начнёт получать сообщения.

---

## 5. Добавление водителей

1. Войти в `/a` → Водители
2. Нажать "Добавить водителя"
3. Указать числовой Telegram ID и имя
4. Водитель теперь будет получать уведомления о новых заказах

---

## 6. Проверка работы

- Сайт: `https://ВАШ_ДОМЕН.railway.app/`
- Админка: `https://ВАШ_ДОМЕН.railway.app/a`
- Заказ: выбрать точки на карте → ввести телефон → нажать кнопку
- Бот: водитель получит сообщение с кнопками ✅/❌

---

## Структура проекта

```
taxi/
├── app.py              # Flask приложение, все маршруты
├── models.py           # SQLAlchemy модели (Order, Driver, Review)
├── telegram_bot.py     # Telegram Bot API (webhook, уведомления)
├── requirements.txt    # Зависимости Python
├── Procfile            # Railway/Gunicorn запуск
├── .env.example        # Пример переменных окружения
├── templates/
│   ├── index.html          # Главная страница (карта + форма заказа)
│   ├── admin_base.html     # Базовый шаблон админки
│   ├── admin_login.html    # Страница входа /a
│   ├── admin_orders.html   # Управление заказами
│   ├── admin_reviews.html  # Модерация отзывов
│   └── admin_drivers.html  # Управление водителями
└── static/
    ├── css/style.css       # Весь CSS (dark glass theme)
    └── js/map.js           # Вся логика карты и форм
```

---

## Локальный запуск (для тестирования)

```bash
# Создать .env файл из примера
cp .env.example .env
# Отредактировать .env — заполнить значения

# Установить зависимости
pip install -r requirements.txt

# Запустить
python app.py
# Открыть: http://localhost:5000
```
