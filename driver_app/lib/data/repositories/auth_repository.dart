import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/storage/token_storage.dart';

class LoginResult {
  final bool ok;
  final bool regulationsAccepted;
  final String? error;
  const LoginResult(this.ok, {this.regulationsAccepted = true, this.error});
}

class AuthRepository {
  final Dio _dio = DioClient.instance.dio;

  Future<LoginResult> login(String phone, String pin) async {
    try {
      final r = await _dio.post('/api/driver/login', data: {
        'phone': phone,
        'pin': pin,
      });
      if (r.statusCode == 200 && r.data is Map && r.data['token'] != null) {
        final data = Map<String, dynamic>.from(r.data as Map);
        await TokenStorage.instance.saveToken(data['token'].toString());
        final driver = data['driver'];
        if (driver is Map) {
          await TokenStorage.instance.saveProfile(
            name: driver['name']?.toString(),
            phone: driver['phone']?.toString(),
          );
        }
        return LoginResult(true,
            regulationsAccepted: data['regulations_accepted'] == true);
      }
      final err = (r.data is Map ? r.data['error'] : null)?.toString();
      return LoginResult(false, error: err ?? 'Неверный телефон или PIN');
    } on DioException catch (_) {
      return const LoginResult(false,
          error: 'Нет связи. Проверьте интернет и попробуйте снова');
    } catch (_) {
      return const LoginResult(false, error: 'Что-то пошло не так');
    }
  }

  Future<bool> acceptRegulations() async {
    try {
      final r = await _dio.post('/driver/regulations/accept');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> registerFcmToken(String token) async {
    try {
      await _dio.post('/driver/api/fcm-token',
          data: {'token': token, 'platform': 'android'});
    } catch (_) {/* не критично */}
  }

  Future<void> logout() async {
    await TokenStorage.instance.clear();
  }
}
