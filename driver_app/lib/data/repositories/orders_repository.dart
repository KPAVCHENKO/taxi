import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/orders_state.dart';

/// Результат изменяющего действия.
class ActionResult {
  final bool ok;
  final int? status;
  final String? error;
  const ActionResult(this.ok, {this.status, this.error});
}

class OrdersRepository {
  final Dio _dio = DioClient.instance.dio;

  Future<OrdersState> fetch() async {
    final r = await _dio.get('/driver/api/orders');
    if (r.statusCode == 200 && r.data is Map) {
      return OrdersState.fromJson(Map<String, dynamic>.from(r.data as Map));
    }
    throw DioException(requestOptions: r.requestOptions, response: r);
  }

  Future<ActionResult> accept(int orderId) =>
      _post('/driver/order/$orderId/accept');

  Future<ActionResult> complete(int orderId, int actualPrice) =>
      _post('/driver/order/$orderId/complete', data: {'actual_price': actualPrice});

  Future<ActionResult> cancel(int orderId) =>
      _post('/driver/order/$orderId/cancel');

  Future<ActionResult> arrived(int orderId) =>
      _post('/driver/order/$orderId/arrived');

  Future<ActionResult> setOnline(bool online) =>
      _post('/driver/status', data: {'online': online});

  Future<List<Map<String, dynamic>>> chatGet(int orderId, int after) async {
    try {
      final r = await _dio.get('/driver/order/$orderId/chat',
          queryParameters: {'after': after});
      final list = (r.data is Map ? r.data['messages'] : null) as List? ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<ActionResult> chatSend(int orderId, String body) =>
      _post('/driver/order/$orderId/chat', data: {'body': body});

  Future<ActionResult> _post(String path, {Object? data}) async {
    try {
      final r = await _dio.post(path, data: data);
      if (r.statusCode != null && r.statusCode! >= 200 && r.statusCode! < 300) {
        return ActionResult(true, status: r.statusCode);
      }
      final err = (r.data is Map ? r.data['error'] : null)?.toString();
      return ActionResult(false, status: r.statusCode, error: err);
    } on DioException catch (e) {
      return ActionResult(false, status: e.response?.statusCode, error: 'network');
    }
  }
}
