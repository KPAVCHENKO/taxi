import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../network/dio_client.dart';
import 'apk_installer.dart';

class UpdateInfo {
  final int versionCode;
  final String url;
  final String notes;
  final bool mandatory;
  const UpdateInfo({required this.versionCode, required this.url, required this.notes, required this.mandatory});
  String get absoluteUrl => url.startsWith('http') ? url : '${AppConfig.baseUrl}$url';
}

Future<UpdateInfo?> _check() async {
  try {
    final r = await DioClient.instance.dio.get('/api/client/app-version');
    if (r.statusCode == 200 && r.data is Map) {
      final m = Map<String, dynamic>.from(r.data as Map);
      final vc = int.tryParse('${m['version_code']}') ?? 1;
      if (vc > AppConfig.appVersionCode) {
        return UpdateInfo(
          versionCode: vc,
          url: (m['url'] ?? '/download/app').toString(),
          notes: (m['notes'] ?? '').toString(),
          mandatory: m['mandatory'] == true,
        );
      }
    }
  } catch (_) {}
  return null;
}

const _kSnoozed = 'client_update_snoozed';

Future<void> _open(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  bool ok = false;
  try { ok = await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
  if (!ok) { try { ok = await launchUrl(uri, mode: LaunchMode.platformDefault); } catch (_) {} }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Не удалось открыть загрузку. Откройте сайт вручную.')),
    );
  }
}

Future<void> runUpdateCheck(BuildContext context, {bool manual = false}) async {
  final info = await _check();
  if (!context.mounted) return;
  if (info == null) {
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('У вас последняя версия')));
    }
    return;
  }
  if (!manual && !info.mandatory) {
    final prefs = await SharedPreferences.getInstance();
    if (info.versionCode <= (prefs.getInt(_kSnoozed) ?? 0)) return;
    if (!context.mounted) return;
  }
  final p = palette(context);
  await showDialog(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.surface,
      title: const Text('Доступно обновление'),
      content: Text(info.notes.isEmpty ? 'Вышла новая версия приложения.' : info.notes),
      actions: [
        if (!info.mandatory)
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setInt(_kSnoozed, info.versionCode);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Позже'),
          ),
        ElevatedButton(
          onPressed: () async {
            if (ctx.mounted) Navigator.pop(ctx);
            final ok = await ApkInstaller.downloadAndInstall(context, info.absoluteUrl);
            if (!ok && context.mounted) await _open(context, info.absoluteUrl);
          },
          child: const Text('Обновить'),
        ),
      ],
    ),
  );
}
