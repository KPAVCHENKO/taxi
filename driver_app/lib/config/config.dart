/// Глобальная конфигурация приложения водителя.
/// Все «магические» значения вынесены сюда — менять только тут.
class AppConfig {
  AppConfig._();

  /// Базовый URL бэкенда (Flask на Railway).
  static const String baseUrl = 'https://kazanskoe-taxi.xyz';

  // ── Тайминги ───────────────────────────────────────────────────────────────
  /// Таймер кольца на экране входящего заказа.
  static const int ringTimeoutSeconds = 60;

  /// Поллинг ленты заказов в foreground, когда на смене.
  static const Duration ordersPollForeground = Duration(seconds: 15);

  /// Поллинг внутри foreground-сервиса (резерв к push).
  static const Duration ordersPollBackground = Duration(seconds: 25);

  /// Поллинг чата, пока открыт экран чата.
  static const Duration chatPoll = Duration(seconds: 4);

  /// Порог низкого баланса для предупреждения (₽).
  static const int lowBalanceThreshold = 0;

  // ── Каналы уведомлений ───────────────────────────────────────────────────────
  static const String channelOrders = 'incoming_orders';
  static const String channelOrdersName = 'Входящие заказы';
  static const String channelChat = 'chat_messages';
  static const String channelChatName = 'Сообщения чата';
  static const String channelShift = 'shift_status';
  static const String channelShiftName = 'Статус смены';

  // ── Контакты ─────────────────────────────────────────────────────────────────
  static const String dispatcherPhone = '+79630608419';
}

/// Подписи для значений с бэкенда. Неизвестное — показываем как есть.
class Labels {
  Labels._();

  static String payment(String? raw) {
    switch (raw) {
      case 'cash':
      case 'Наличные':
        return 'Наличные';
      case 'transfer':
      case 'card':
      case 'Перевод':
        return 'Перевод';
      default:
        return raw ?? '';
    }
  }

  static String rideType(String? raw) {
    switch (raw) {
      case 'shared':
      case 'Попутчики':
        return 'Попутно';
      case 'individual':
      case 'Индивидуально':
        return 'Индивидуально';
      default:
        return raw ?? '';
    }
  }
}
