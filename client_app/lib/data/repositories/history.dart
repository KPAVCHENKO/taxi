import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Локальная история заказов (без аккаунта).
class History {
  History._();
  static const _key = 'my_orders';

  static Future<List<MyOrder>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final list = <MyOrder>[];
    for (final s in raw) {
      try {
        list.add(MyOrder.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    list.sort((a, b) => b.ts.compareTo(a.ts));
    return list;
  }

  static Future<void> add(MyOrder o) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.insert(0, jsonEncode(o.toJson()));
    // храним последние 30
    await prefs.setStringList(_key, raw.take(30).toList());
  }

  /// Самый свежий активный заказ (для экрана статуса при перезаходе).
  static Future<MyOrder?> latest() async {
    final list = await load();
    return list.isEmpty ? null : list.first;
  }
}
