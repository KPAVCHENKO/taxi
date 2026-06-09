import 'package:url_launcher/url_launcher.dart';

/// Открыть навигацию к точке (Яндекс.Навигатор → 2ГИС → любые карты → веб).
class Navigation {
  Navigation._();

  static Future<void> route({double? lat, double? lon, String? address}) async {
    final tries = <Uri>[];
    if (lat != null && lon != null) {
      tries.add(Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon'));
      tries.add(Uri.parse('dgis://2gis.ru/routeSearch/rsType/car/to/$lon,$lat'));
      tries.add(Uri.parse('geo:$lat,$lon?q=$lat,$lon'));
      tries.add(Uri.parse('https://yandex.ru/maps/?rtext=~$lat,$lon&rtt=auto'));
    } else if (address != null && address.trim().isNotEmpty) {
      final q = Uri.encodeComponent(address.trim());
      tries.add(Uri.parse('yandexnavi://map_search?text=$q'));
      tries.add(Uri.parse('geo:0,0?q=$q'));
      tries.add(Uri.parse('https://yandex.ru/maps/?text=$q'));
    }
    for (final uri in tries) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {/* нет приложения для схемы — пробуем следующее */}
    }
  }
}
