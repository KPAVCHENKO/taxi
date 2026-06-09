import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FavPlace {
  final String label; // Дом / Работа / своё
  final String address;
  final String? key;
  final double? lat, lon;
  const FavPlace({required this.label, required this.address, this.key, this.lat, this.lon});

  Map<String, dynamic> toJson() =>
      {'label': label, 'address': address, 'key': key, 'lat': lat, 'lon': lon};

  factory FavPlace.fromJson(Map<String, dynamic> j) => FavPlace(
        label: (j['label'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        key: j['key']?.toString(),
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
      );
}

class Favorites {
  Favorites._();
  static const _k = 'favorites';

  static Future<List<FavPlace>> load() async {
    final p = await SharedPreferences.getInstance();
    final out = <FavPlace>[];
    for (final s in p.getStringList(_k) ?? []) {
      try {
        out.add(FavPlace.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> add(FavPlace f) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_k) ?? [];
    raw.add(jsonEncode(f.toJson()));
    await p.setStringList(_k, raw.take(8).toList());
  }

  static Future<void> removeAt(int i) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_k) ?? [];
    if (i >= 0 && i < raw.length) {
      raw.removeAt(i);
      await p.setStringList(_k, raw);
    }
  }
}
