import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Скачать APK внутри приложения (с прогрессом) и открыть системный установщик.
class ApkInstaller {
  static Future<bool> downloadAndInstall(BuildContext context, String url) async {
    String abi = '';
    try {
      final di = await DeviceInfoPlugin().androidInfo;
      if (di.supportedAbis.isNotEmpty) abi = di.supportedAbis.first;
    } catch (_) {}
    final dlUrl = '$url${url.contains('?') ? '&' : '?'}abi=$abi';

    final progress = ValueNotifier<double>(0);
    bool dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Загрузка обновления'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (c, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v > 0 ? v : null),
              const SizedBox(height: 12),
              Text(v > 0 ? '${(v * 100).toStringAsFixed(0)} %' : 'Подождите…'),
            ],
          ),
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/update.apk';
      await Dio().download(dlUrl, path, onReceiveProgress: (r, t) {
        if (t > 0) progress.value = r / t;
      });
      closeDialog();
      final res = await OpenFilex.open(path);
      return res.type == ResultType.done;
    } catch (_) {
      closeDialog();
      return false;
    }
  }
}
