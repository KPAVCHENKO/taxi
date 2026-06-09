import 'package:dio/dio.dart';

import '../../config/config.dart';
import '../storage/token_storage.dart';

/// Сигнал «нас разлогинило» (любой 401). Слушает корень приложения.
typedef UnauthorizedHandler = void Function();

class DioClient {
  DioClient._();
  static final DioClient instance = DioClient._();

  UnauthorizedHandler? onUnauthorized;

  late final Dio dio = _build();

  Dio _build() {
    final d = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json'},
      // не бросать на 4xx — обрабатываем коды сами
      validateStatus: (s) => s != null && s < 500,
    ));

    d.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.instance.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (response.statusCode == 401) {
          _handleUnauthorized();
        }
        handler.next(response);
      },
      onError: (e, handler) {
        if (e.response?.statusCode == 401) {
          _handleUnauthorized();
        }
        handler.next(e);
      },
    ));

    return d;
  }

  bool _loggingOut = false;
  void _handleUnauthorized() {
    if (_loggingOut) return;
    _loggingOut = true;
    TokenStorage.instance.clear();
    onUnauthorized?.call();
    Future.delayed(const Duration(seconds: 2), () => _loggingOut = false);
  }
}
