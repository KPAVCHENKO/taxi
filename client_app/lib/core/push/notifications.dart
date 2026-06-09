import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/config.dart';

class Notifications {
  Notifications._();
  static final instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.createNotificationChannel(const AndroidNotificationChannel(
      AppConfig.channelStatus,
      AppConfig.channelStatusName,
      description: 'Статус вашего заказа такси',
      importance: Importance.high,
    ));
    _inited = true;
  }

  Future<void> requestPermission() async {
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await impl?.requestNotificationsPermission();
  }

  Future<void> showStatus(String title, String body) async {
    const details = AndroidNotificationDetails(
      AppConfig.channelStatus,
      AppConfig.channelStatusName,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      7001,
      title,
      body,
      const NotificationDetails(android: details),
    );
  }
}
