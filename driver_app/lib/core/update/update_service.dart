import '../../config/config.dart';
import '../network/dio_client.dart';

class UpdateInfo {
  final int versionCode;
  final String url;
  final String notes;
  final bool mandatory;
  const UpdateInfo({
    required this.versionCode,
    required this.url,
    required this.notes,
    required this.mandatory,
  });

  /// Абсолютный URL для скачивания APK.
  String get absoluteUrl =>
      url.startsWith('http') ? url : '${AppConfig.baseUrl}$url';
}

/// Самообновление без Google Play: сверяем код версии с сервером.
class UpdateService {
  Future<UpdateInfo?> check() async {
    try {
      final r = await DioClient.instance.dio.get('/api/driver/app-version');
      if (r.statusCode == 200 && r.data is Map) {
        final m = Map<String, dynamic>.from(r.data as Map);
        final vc = int.tryParse('${m['version_code']}') ?? 1;
        if (vc > AppConfig.appVersionCode) {
          return UpdateInfo(
            versionCode: vc,
            url: (m['url'] ?? '/download/driver').toString(),
            notes: (m['notes'] ?? '').toString(),
            mandatory: m['mandatory'] == true,
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
