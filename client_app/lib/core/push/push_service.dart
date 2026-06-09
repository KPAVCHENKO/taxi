import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'notifications.dart';

/// Фоновый обработчик: показать уведомление о статусе заказа.
@pragma('vm:entry-point')
Future<void> clientBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final d = message.data;
  if (d['type'] == 'order_status') {
    await Notifications.instance.init();
    await Notifications.instance.showStatus(
      d['title']?.toString() ?? 'Статус заказа',
      d['body']?.toString() ?? '',
    );
  }
}

class PushService {
  PushService._();
  static final instance = PushService._();

  final _fm = FirebaseMessaging.instance;
  String? _token;

  /// Колбэк обновления статуса (экран статуса слушает).
  void Function(RemoteMessage msg)? onStatusMessage;

  Future<void> init() async {
    await Notifications.instance.init();
    await _fm.requestPermission(alert: true, badge: true, sound: true);
    try {
      _token = await _fm.getToken();
    } catch (_) {}
    _fm.onTokenRefresh.listen((t) => _token = t);

    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onForeground);
  }

  String? get token => _token;

  Future<String?> ensureToken() async {
    _token ??= await _fm.getToken();
    return _token;
  }

  void _onForeground(RemoteMessage message) {
    final d = message.data;
    if (d['type'] == 'order_status') {
      Notifications.instance.showStatus(
        d['title']?.toString() ?? 'Статус заказа',
        d['body']?.toString() ?? '',
      );
      onStatusMessage?.call(message);
    }
  }
}
