import 'package:url_launcher/url_launcher.dart';

/// Построить маршрут к точке.
/// Есть координаты → Яндекс.Навигатор / 2ГИS / Яндекс.Карты строят маршрут по точке.
/// Нет координат → Яндекс.Карты строят маршрут от текущего места к адресу (геокодят текст).
class Navigation {
  Navigation._();

  static String _dest(String a) =>
      a.toLowerCase().contains('област') ? a : '$a, Тюменская область';

  static Future<void> route({double? lat, double? lon, String? address}) async {
    final tries = <Uri>[];
    if (lat != null && lon != null) {
      tries.add(Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon'));
      tries.add(Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lon,$lat'));
      tries.add(Uri.parse('https://yandex.ru/maps/?rtext=~$lat,$lon&rtt=auto'));
    } else if (address != null && address.trim().isNotEmpty) {
      final q = Uri.encodeComponent(_dest(address.trim()));
      // Маршрут от текущего местоположения к адресу (Яндекс геокодит текст).
      tries.add(Uri.parse('https://yandex.ru/maps/?rtext=~$q&rtt=auto'));
      tries.add(Uri.parse('geo:0,0?q=$q'));
    }
    for (final uri in tries) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {/* нет приложения для схемы — пробуем следующее */}
    }
  }
}
