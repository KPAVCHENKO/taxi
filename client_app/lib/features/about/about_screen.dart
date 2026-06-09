import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../core/update/update_service.dart';
import '../../widgets/ui.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              children: [
                Text('🚖', style: TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text('Казанское Такси', style: heading(size: 20, color: p.text)),
                const SizedBox(height: 4),
                Text('Такси по Казанскому району', style: TextStyle(color: p.text3)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _tile(context, Icons.phone, 'Позвонить диспетчеру', () => _call()),
          _tile(context, Icons.system_update, 'Проверить обновление', () => runUpdateCheck(context, manual: true)),
          _tile(context, Icons.description_outlined, 'Условия использования Яндекс.Карт', () => _open(AppConfig.yandexTermsUrl)),
          const SizedBox(height: 20),
          Center(child: Text('Версия 1.0.0', style: TextStyle(color: p.text3, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    final p = palette(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: p.accent),
        title: Text(title, style: TextStyle(fontSize: 16, color: p.text)),
        trailing: Icon(Icons.chevron_right, color: p.text3),
        onTap: onTap,
      ),
    );
  }

  Future<void> _call() async {
    try { await launchUrl(Uri.parse('tel:${AppConfig.dispatcherPhone}'), mode: LaunchMode.externalApplication); } catch (_) {}
  }

  Future<void> _open(String url) async {
    try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {}
  }
}
