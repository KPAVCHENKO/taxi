/// Конфигурация пользовательского приложения.
class AppConfig {
  AppConfig._();

  static const String baseUrl = 'https://kazanskoe-taxi.xyz';
  static const String dispatcherPhone = '+79630608419';
  static const String yandexTermsUrl = 'https://yandex.ru/legal/maps_api/';

  /// Код версии сборки (сверяется с /api/client/app-version).
  static const int appVersionCode = 3;

  /// Поллинг статуса заказа, пока открыт экран статуса.
  static const Duration statusPoll = Duration(seconds: 10);

  static const String channelStatus = 'order_status';
  static const String channelStatusName = 'Статус заказа';
}

/// Один населённый пункт для выбора.
class Settle {
  final String key; // ключ для тарифа (lowercase, как на сайте)
  final String label; // что показываем
  final bool intercity;
  const Settle(this.key, this.label, {this.intercity = false});
}

/// Список населённых пунктов (Казанское — хаб, сёла, межгород).
class Settlements {
  Settlements._();
  static const String hub = 'казанское';

  static const List<Settle> all = [
    Settle('казанское', 'Казанское'),
    Settle('новоселезнево', 'Новоселезнёво'),
    Settle('шадринка', 'Шадринка'),
    Settle('яровское', 'Яровское'),
    Settle('большие ярки', 'Большие Ярки'),
    Settle('малые ярки', 'Малые Ярки'),
    Settle('гагарье', 'Гагарье'),
    Settle('сладчанка', 'Сладчанка'),
    Settle('боровлянка', 'Боровлянка'),
    Settle('дальнетравное', 'Дальнетравное'),
    Settle('ильинка', 'Ильинка'),
    Settle('кугаево', 'Кугаево'),
    Settle('чирки', 'Чирки'),
    Settle('огнево', 'Огнёво'),
    Settle('дубынка', 'Дубынка'),
    Settle('заречка', 'Заречка'),
    Settle('смирное', 'Смирное'),
    Settle('афонькино', 'Афонькино'),
    Settle('пешнево', 'Пешнёво'),
    Settle('копотилово', 'Копотилово'),
    Settle('ченчерь', 'Ченчерь'),
    Settle('ельцово', 'Ельцово'),
    Settle('коротаевка', 'Коротаевка'),
    Settle('грачи', 'Грачи'),
    Settle('паленка', 'Палёнка'),
    Settle('новогеоргиевка', 'Новогеоргиевка'),
    Settle('новоалександровка', 'Новоалександровка'),
    Settle('челюскинцев', 'Челюскинцев'),
    Settle('викторовка', 'Викторовка'),
    Settle('долматово', 'Долматово'),
    Settle('ишим', 'Ишим (межгород)', intercity: true),
    Settle('петропавловск', 'Петропавловск (межгород)', intercity: true),
  ];

  static Settle? byKey(String? key) {
    if (key == null) return null;
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }

  static Settle? byLabel(String? label) {
    if (label == null) return null;
    for (final s in all) {
      if (s.label == label) return s;
    }
    return null;
  }
}
