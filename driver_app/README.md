# Казанское Такси — приложение водителя (Flutter)

Нативное Android-приложение водителя поверх существующего бэкенда
(Flask на `https://kazanskoe-taxi.xyz`). GPS/карт нет — сознательно.

Что внутри: вход по телефону+PIN (JWT), полноэкранный «входящий заказ» (звонок)
поверх блокировки, FCM-push, foreground-сервис «На смене», чат с диспетчером,
история, баланс, самообновление, инструкции по энергосбережению.

---

## 0. Что уже готово на бэкенде (ничего дорабатывать не нужно)

- `POST /api/driver/login` `{phone, pin}` → `{token, regulations_accepted, driver}`
- `GET  /driver/api/orders` → лента, мой заказ, история, баланс, заработок, онлайн, непрочитанные чата
- `POST /driver/order/<id>/accept | complete | cancel`
- `POST /driver/status` `{online}`
- `GET  /driver/api/chat?room=group|direct&after=<id>`, `POST /driver/api/chat/send`, `/seen`
- `POST /driver/api/fcm-token` `{token, platform}` — регистрация FCM-токена
- `POST /driver/regulations/accept`
- `GET  /api/driver/app-version` — самообновление
- FCM-события: `new_order` (с полями заказа), `order_taken`, `order_cancelled`, `chat`
  (data-only, high-priority). Включаются, когда в админке заданы Firebase-ключи.

---

## 1. Предварительные требования

- Flutter SDK (stable, Dart 3.3+), Android Studio / Android SDK, **JDK 17**.
- Аккаунт Google для Firebase (бесплатно).

---

## 2. Генерация платформенной обвязки

В папке `driver_app/` уже лежит код `lib/`, `pubspec.yaml`, `AndroidManifest.xml`,
`MainActivity.kt`, иконка уведомления. Доскаффолдьте Gradle/обёртки командой
(она НЕ перезапишет существующие файлы):

```bash
cd driver_app
flutter create --org xyz.kazanskoe --project-name kazanskoe_driver --platforms=android .
flutter pub get
```

`applicationId` должен получиться `xyz.kazanskoe.driver` (совпадает с `MainActivity.kt`).

---

## 3. Firebase (для push)

1. https://console.firebase.google.com → **Add project**.
2. Add app → **Android**, package name: `xyz.kazanskoe.driver`.
3. Скачать **`google-services.json`** → положить в `driver_app/android/app/`.
4. В **Project settings → Service accounts → Generate new private key** скачать JSON.
5. На сайте: админка → **📲 Приложение** → вставить **Project ID** и этот **JSON** → Сохранить.
   (После этого бэкенд начнёт слать FCM.)

---

## 4. Правки Gradle (добавить Firebase + версии SDK)

**`android/settings.gradle`** — в блок `plugins { ... }` добавить:
```groovy
id "com.google.gms.google-services" version "4.4.2" apply false
```

**`android/app/build.gradle`**:
```groovy
plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
    id "com.google.gms.google-services"   // ← добавить
}

android {
    namespace = "xyz.kazanskoe.driver"
    compileSdk = 35                         // требование Google Play

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        applicationId = "xyz.kazanskoe.driver"
        minSdk = 24                          // Android 7.0
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        multiDexEnabled = true
    }
}
```

> Если `flutter pub get` поставит мажорную версию `flutter_foreground_task`, отличную от 8.x —
> сверьте сигнатуры в `lib/core/fgs/shift_service.dart` с README плагина (там чаще всего меняется API).

---

## 5. Запуск и сборка

```bash
flutter run                 # отладка на подключённом телефоне
flutter build apk --release # → build/app/outputs/flutter-apk/app-release.apk
```

APK можно раздавать напрямую (sideload) с сайта `/download/driver`.

---

## 6. Полноэкранный «звонок» (важно)

- Android 14+ требует разрешение **USE_FULL_SCREEN_INTENT** (объявлено в манифесте).
  При первом запуске экран «Надёжная работа» помогает его выдать.
- Если FSI не выдан — приходит громкое heads-up-уведомление со звуком на канале
  «Входящие заказы» (importance MAX), по тапу открывается экран заказа.
- Звук «звонка»: сейчас — системный звук канала + вибрация. Чтобы поставить
  свой рингтон: положите `android/app/src/main/res/raw/ring.mp3` и задайте
  `sound: RawResourceAndroidNotificationSound('ring')` в `lib/core/push/notifications.dart`.

---

## 7. Самообновление без Google Play

Приложение читает `GET /api/driver/app-version`. Когда выложите новый APK —
в админке (📲 Приложение) поднимите **код версии**. (UI-проверку обновления можно
включить в `MoreScreen`/при старте — эндпоинт уже готов.)

---

## 8. Структура

```
lib/
  config/        конфиг, тема
  core/network/  dio + AuthInterceptor (Bearer, 401→logout)
  core/storage/  secure storage (JWT)
  core/push/     FCM + локальные уведомления (полноэкранный заказ)
  core/fgs/      foreground-сервис «На смене»
  data/models/   Order, OrdersState, ChatMessage
  data/repositories/  auth, orders, chat
  state/         Riverpod-провайдеры + OrdersController (поллинг, действия)
  features/      splash, auth, regulations, home, shift, orders,
                 incoming_call, chat, history, more, instructions
  widgets/       OrderCard
```

Единый источник истины — `GET /driver/api/orders` (`OrdersController`), обновляется
по push, поллингом (15с в foreground), и после каждого действия.
