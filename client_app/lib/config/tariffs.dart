import 'config.dart';

/// Тарифы: фикс-цены по сёлам (относительно Казанского) + межгород.
/// Дефолты — как на сайте; могут переопределяться из GET /api/tariffs.
class Tariffs {
  Tariffs._();

  static Map<String, int> local = {
    'казанское': 150, 'новоселезнево': 200, 'шадринка': 300, 'яровское': 300,
    'большие ярки': 300, 'малые ярки': 400, 'гагарье': 500, 'сладчанка': 500,
    'боровлянка': 600, 'дальнетравное': 600, 'ильинка': 700, 'кугаево': 700,
    'чирки': 700, 'огнево': 800, 'дубынка': 900, 'заречка': 900, 'смирное': 900,
    'афонькино': 1000, 'пешнево': 1000, 'копотилово': 1000, 'ченчерь': 1000,
    'ельцово': 1000, 'коротаевка': 1100, 'грачи': 1200, 'паленка': 1200,
    'новогеоргиевка': 1500, 'новоалександровка': 1500, 'челюскинцев': 1500,
    'викторовка': 1800, 'долматово': 1800,
  };

  static Map<String, int> intercity = {
    'ишим': 2000, 'петропавловск': 5000,
  };

  /// Подмешать тарифы из API.
  static void mergeFromApi(Map<String, dynamic> data) {
    final loc = data['local'];
    if (loc is Map) {
      loc.forEach((k, v) {
        final price = (v is num) ? v.toInt() : int.tryParse('$v');
        if (price != null) local[k.toString().toLowerCase()] = price;
      });
    }
    final ic = data['intercity'];
    if (ic is Map) {
      ic.forEach((k, v) {
        if (v is Map && v['one_way'] != null) {
          final price = (v['one_way'] is num)
              ? (v['one_way'] as num).toInt()
              : int.tryParse('${v['one_way']}');
          if (price != null) intercity[k.toString().toLowerCase()] = price;
        }
      });
    }
  }

  /// Цена по ключам населённых пунктов. null — «уточнит диспетчер».
  static int? price(String? fromKey, String? toKey) {
    if (fromKey == null || toKey == null) return null;
    if (intercity.containsKey(fromKey)) return intercity[fromKey];
    if (intercity.containsKey(toKey)) return intercity[toKey];
    String? dest;
    if (fromKey == Settlements.hub) {
      dest = toKey;
    } else if (toKey == Settlements.hub) {
      dest = fromKey;
    } else {
      return null; // ни один не Казанское — диспетчер уточнит
    }
    return local[dest];
  }
}
