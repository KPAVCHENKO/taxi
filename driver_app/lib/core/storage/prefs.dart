import 'package:shared_preferences/shared_preferences.dart';

/// Локальные настройки приложения водителя (звук/вибрация входящего заказа).
class Prefs {
  Prefs._();

  static const _kSound = 'opt_sound';
  static const _kVibe = 'opt_vibration';

  static bool sound = true;
  static bool vibration = true;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound = p.getBool(_kSound) ?? true;
    vibration = p.getBool(_kVibe) ?? true;
  }

  static Future<void> setSound(bool v) async {
    sound = v;
    (await SharedPreferences.getInstance()).setBool(_kSound, v);
  }

  static Future<void> setVibration(bool v) async {
    vibration = v;
    (await SharedPreferences.getInstance()).setBool(_kVibe, v);
  }
}
