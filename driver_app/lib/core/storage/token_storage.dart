import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранение JWT в Android Keystore через flutter_secure_storage.
class TokenStorage {
  TokenStorage._();
  static final instance = TokenStorage._();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kToken = 'jwt_token';
  static const _kDriverName = 'driver_name';
  static const _kDriverPhone = 'driver_phone';

  String? _cached;

  Future<String?> getToken() async {
    _cached ??= await _storage.read(key: _kToken);
    return _cached;
  }

  String? get cachedToken => _cached;

  Future<void> saveToken(String token) async {
    _cached = token;
    await _storage.write(key: _kToken, value: token);
  }

  Future<void> saveProfile({String? name, String? phone}) async {
    if (name != null) await _storage.write(key: _kDriverName, value: name);
    if (phone != null) await _storage.write(key: _kDriverPhone, value: phone);
  }

  Future<String?> get driverName => _storage.read(key: _kDriverName);
  Future<String?> get driverPhone => _storage.read(key: _kDriverPhone);

  Future<void> clear() async {
    _cached = null;
    await _storage.deleteAll();
  }
}
