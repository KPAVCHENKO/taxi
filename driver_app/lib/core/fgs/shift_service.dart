import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../config/config.dart';

/// Foreground-сервис на время смены: постоянное уведомление «Вы на смене»
/// держит процесс живым (надёжнее доходит FCM, не выгружается на Samsung/Xiaomi).
///
/// ВНИМАНИЕ: API flutter_foreground_task активно меняется между версиями.
/// Этот файл написан под 8.x. Если pub get поставит другую мажорную версию —
/// поправьте сигнатуры здесь по README плагина.
@pragma('vm:entry-point')
void startShiftCallback() {
  FlutterForegroundTask.setTaskHandler(_ShiftTaskHandler());
}

class _ShiftTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Сигнал главному isolate — обновить ленту (резерв к push).
    FlutterForegroundTask.sendDataToMain('tick');
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class ShiftService {
  ShiftService._();

  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: AppConfig.channelShift,
        channelName: AppConfig.channelShiftName,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          AppConfig.ordersPollBackground.inMilliseconds,
        ),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'Вы на смене',
      notificationText: 'Казанское Такси — принимаем заказы',
      callback: startShiftCallback,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static void onTick(void Function() cb) {
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data == 'tick') cb();
    });
  }
}
