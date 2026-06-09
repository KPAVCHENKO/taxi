import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../config/config.dart';
import '../../data/models/order.dart';

/// Локальные уведомления + каналы. Главный канал «Входящие заказы» —
/// максимальной важности с full-screen intent (показ поверх блокировки).
class Notifications {
  Notifications._();
  static final instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// Колбэк при тапе по уведомлению (payload = order_id для заказа).
  void Function(String? payload)? onTap;

  Future<void> init() async {
    if (_inited) return;
    const androidInit = AndroidInitializationSettings('notif_icon');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) => onTap?.call(resp.payload),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      AppConfig.channelOrders,
      AppConfig.channelOrdersName,
      description: 'Новые заказы — показываются как входящий звонок',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      AppConfig.channelChat,
      AppConfig.channelChatName,
      description: 'Сообщения от диспетчера',
      importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      AppConfig.channelShift,
      AppConfig.channelShiftName,
      description: 'Статус смены',
      importance: Importance.low,
    ));
    _inited = true;
  }

  Future<void> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// Полноэкранное уведомление о заказе (срабатывает поверх блокировки,
  /// если выдано разрешение USE_FULL_SCREEN_INTENT; иначе — громкий heads-up).
  Future<void> showIncomingOrder(TaxiOrder order) async {
    final details = AndroidNotificationDetails(
      AppConfig.channelOrders,
      AppConfig.channelOrdersName,
      channelDescription: 'Новый заказ',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ticker: 'Новый заказ',
    );
    await _plugin.show(
      _orderNotifId,
      '🚖 Новый заказ',
      '${order.fromAddress} → ${order.toAddress}',
      NotificationDetails(android: details),
      payload: 'order:${order.id}',
    );
  }

  Future<void> cancelIncoming() => _plugin.cancel(_orderNotifId);

  Future<void> showChat(String title, String body, String room) async {
    const details = AndroidNotificationDetails(
      AppConfig.channelChat,
      AppConfig.channelChatName,
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      room.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(android: details),
      payload: 'chat:$room',
    );
  }

  /// Детали запуска приложения по тапу на уведомление (terminated).
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp == true) {
      return d!.notificationResponse?.payload;
    }
    return null;
  }

  static const int _orderNotifId = 1001;
}
