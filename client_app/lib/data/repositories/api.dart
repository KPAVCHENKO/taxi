import 'package:dio/dio.dart';

import '../../config/tariffs.dart';
import '../../core/network/dio_client.dart';
import '../models/models.dart';

class CreateResult {
  final bool ok;
  final int? orderId;
  final String? token;
  final bool noDriversOnline;
  final String? error;
  const CreateResult(this.ok, {this.orderId, this.token, this.noDriversOnline = false, this.error});
}

class Api {
  final Dio _dio = DioClient.instance.dio;

  /// Подтянуть тарифы (необязательно — есть фолбэк).
  Future<void> loadTariffs() async {
    try {
      final r = await _dio.get('/api/tariffs');
      if (r.statusCode == 200 && r.data is Map) {
        Tariffs.mergeFromApi(Map<String, dynamic>.from(r.data as Map));
      }
    } catch (_) {}
  }

  Future<CreateResult> createOrder(Map<String, dynamic> body) async {
    try {
      final r = await _dio.post('/order', data: body);
      final d = (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : {};
      if (r.statusCode == 200 && d['success'] == true) {
        return CreateResult(true,
            orderId: d['order_id'] as int?,
            token: d['cancel_token']?.toString(),
            noDriversOnline: d['no_drivers_online'] == true);
      }
      if (r.statusCode == 429) {
        return const CreateResult(false, error: 'Слишком много заказов подряд. Позвоните диспетчеру.');
      }
      return CreateResult(false, error: (d['error'] ?? 'Не удалось оформить заказ').toString());
    } on DioException catch (_) {
      return const CreateResult(false, error: 'Нет связи. Проверьте интернет и попробуйте снова');
    }
  }

  Future<OrderStatus?> getStatus(int orderId, String token) async {
    try {
      final r = await _dio.get('/order/$orderId/status', queryParameters: {'token': token});
      if (r.statusCode == 200 && r.data is Map) {
        return OrderStatus.fromJson(Map<String, dynamic>.from(r.data as Map));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> cancel(int orderId, String token) async {
    try {
      final r = await _dio.post('/order/$orderId/cancel', data: {'token': token});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rate(int orderId, String token, int rating) async {
    try {
      final r = await _dio.post('/order/$orderId/rate',
          data: {'token': token, 'rating': rating});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Review>> getReviews() async {
    try {
      final r = await _dio.get('/api/reviews');
      if (r.statusCode == 200 && r.data is Map) {
        final list = (r.data['reviews'] as List? ?? []);
        return list
            .map((e) => Review((e['name'] ?? '').toString(), (e['text'] ?? '').toString()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> sendReview({required String name, required String text, required String type}) async {
    try {
      final r = await _dio.post('/review', data: {'name': name, 'text': text, 'type': type});
      final d = (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : {};
      return r.statusCode == 200 && d['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
