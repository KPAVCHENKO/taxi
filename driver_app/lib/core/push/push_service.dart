import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/order.dart';
import '../../data/repositories/auth_repository.dart';
import '../../state/orders_controller.dart';
import 'notifications.dart';

/// Фоновый обработчик FCM (отдельный isolate). Для data-only new_order
/// показываем полноэкранное уведомление, которое разбудит экран звонка.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  final type = data['type'];
  await Notifications.instance.init();
  if (type == 'new_order') {
    await Notifications.instance.showIncomingOrder(TaxiOrder.fromFcm(data));
  } else if (type == 'order_taken' || type == 'order_cancelled') {
    await Notifications.instance.cancelIncoming();
  } else if (type == 'chat') {
    await Notifications.instance.showChat(
      data['title']?.toString() ?? '💬 Сообщение',
      data['body']?.toString() ?? '',
      data['room']?.toString() ?? 'group',
    );
  }
}

/// Глобальный доступ к push-сервису (переинициализация после логина).
PushService? gPush;

class PushService {
  PushService(this._container);
  final ProviderContainer _container;

  final _fm = FirebaseMessaging.instance;

  OrdersController get _orders =>
      _container.read(ordersControllerProvider.notifier);

  Future<void> init() async {
    await Notifications.instance.init();
    Notifications.instance.onTap = _onNotificationTap;

    await _fm.requestPermission(alert: true, badge: true, sound: true);

    // Регистрация токена на бэкенде
    await _registerToken();
    _fm.onTokenRefresh.listen((t) => AuthRepository().registerFcmToken(t));

    // Foreground
    FirebaseMessaging.onMessage.listen(_onForeground);
    // Тап по notification-сообщению (если придёт такой тип)
    FirebaseMessaging.onMessageOpenedApp.listen(_onForeground);

    // Холодный старт по уведомлению
    final initial = await _fm.getInitialMessage();
    if (initial != null) _onForeground(initial);
    final payload = await Notifications.instance.launchPayload();
    if (payload != null) _onNotificationTap(payload);
  }

  Future<void> _registerToken() async {
    try {
      final t = await _fm.getToken();
      if (t != null) await AuthRepository().registerFcmToken(t);
    } catch (_) {}
  }

  void _onForeground(RemoteMessage message) {
    final data = message.data;
    switch (data['type']) {
      case 'new_order':
        _orders.onPushNewOrder(TaxiOrder.fromFcm(data));
        break;
      case 'order_taken':
      case 'order_cancelled':
        final id = int.tryParse('${data['order_id']}');
        Notifications.instance.cancelIncoming();
        if (id != null) _orders.onOrderGone(id);
        break;
      case 'chat':
        _orders.refresh(silent: true);
        break;
      default:
        _orders.refresh(silent: true);
    }
  }

  void _onNotificationTap(String? payload) {
    if (payload == null) return;
    if (payload.startsWith('order:')) {
      _orders.refresh(silent: true); // экран звонка поднимется из состояния
    }
  }

  Future<void> deleteToken() async {
    try {
      await _fm.deleteToken();
    } catch (_) {}
  }
}
