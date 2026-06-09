import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/chat_message.dart';

class ChatRepository {
  final Dio _dio = DioClient.instance.dio;

  Future<List<ChatMessage>> fetch(String room, {int after = 0}) async {
    final r = await _dio.get('/driver/api/chat',
        queryParameters: {'room': room, 'after': after});
    if (r.statusCode == 200 && r.data is Map) {
      final list = (r.data['messages'] as List? ?? []);
      return list
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return const [];
  }

  Future<bool> send(String room, String body) async {
    try {
      final r = await _dio.post('/driver/api/chat/send',
          data: {'room': room, 'body': body});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> seen(String room) async {
    try {
      await _dio.post('/driver/api/chat/seen', data: {'room': room});
    } catch (_) {}
  }
}
