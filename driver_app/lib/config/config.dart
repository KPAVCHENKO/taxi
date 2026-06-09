/// Глобальная конфигурация приложения водителя.
/// Все «магические» значения вынесены сюда — менять только тут.
class AppConfig {
  AppConfig._();

  /// Базовый URL бэкенда (Flask на Railway).
  static const String baseUrl = 'https://kazanskoe-taxi.xyz';

  /// Код версии этой сборки. Поднимайте вместе с versionCode в build.gradle —
  /// приложение сверяет его с /api/driver/app-version и предлагает обновиться.
  static const int appVersionCode = 4;

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

/// Короткое название из длинного адреса: «Тюменская область, Казанский
/// муниципальный округ, село Ильинка» → «Ильинка» (с улицей, если указана).
class Addr {
  Addr._();

  static const _noise = [
    'область', 'район', 'муниципальн', 'округ', 'край',
    'республика', 'городское поселение', 'сельское поселение', 'россия', 'рф'
  ];
  static const _types = [
    'село ', 'деревня ', 'посёлок ', 'поселок ', 'город ', 'станица ',
    'хутор ', 'аул ', 'пгт ', 'с. ', 'д. ', 'п. ', 'г. ', 'ст. ', 'х. '
  ];

  static String short(String full) {
    if (full.trim().isEmpty) return full;
    final parts =
        full.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    var kept = parts.where((p) {
      final low = p.toLowerCase();
      return !_noise.any((n) => low.contains(n));
    }).toList();
    if (kept.isEmpty) kept = [parts.last];
    // убрать слова-типы («село», «деревня» …) в начале части
    kept = kept.map((p) {
      final low = p.toLowerCase();
      for (final t in _types) {
        if (low.startsWith(t)) return p.substring(t.length).trim();
      }
      return p;
    }).toList();
    return kept.join(', ');
  }

  /// «Казанское → Ильинка»
  static String route(String from, String to) => '${short(from)} → ${short(to)}';
}
