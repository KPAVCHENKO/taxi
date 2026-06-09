import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/theme.dart';

/// Инструкции по энергосбережению для разных прошивок + кнопки-ярлыки.
class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Надёжная работа')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Чтобы заказы приходили даже при закрытом и заблокированном телефоне, '
            'разрешите приложению работать в фоне.',
            style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.text),
          ),
          const SizedBox(height: 20),
          _actionButton('🔋 Отключить экономию батареи', () async {
            await Permission.ignoreBatteryOptimizations.request();
          }),
          _actionButton('🔔 Настройки уведомлений', () {
            openAppSettings();
          }),
          _actionButton('⚙️ Настройки приложения', () {
            openAppSettings();
          }),
          const SizedBox(height: 24),
          _brand('Samsung (One UI)', const [
            'Настройки → Приложения → Казанское Такси → Батарея → «Без ограничений»',
            'Настройки → Батарея → Ограничения в фоне → убрать из «Спящих приложений»',
            'Выключить «Усыплять неиспользуемые приложения»',
          ]),
          _brand('Xiaomi / Redmi / POCO (MIUI/HyperOS)', const [
            'Безопасность → Батарея → Экономия → выбрать «Нет ограничений»',
            'Настройки приложения → Автозапуск → включить',
            'В недавних задачах потянуть карточку вниз → «Закрепить» (замок)',
          ]),
          _brand('Huawei / Honor', const [
            'Настройки → Батарея → Запуск приложения → ручное управление: всё включить',
            'Добавить в «Защищённые приложения»',
          ]),
          _brand('Oppo / Realme / Vivo', const [
            'Настройки → Батарея → разрешить работу в фоне',
            'Автозапуск → включить для приложения',
          ]),
          _brand('Чистый Android', const [
            'Настройки → Приложения → Казанское Такси → Батарея → «Без ограничений»',
          ]),
          const SizedBox(height: 16),
          const Text(
            'Совет: держите приложение в недавних задачах закреплённым (замок), '
            'чтобы система его не выгружала.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 54,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface2,
            foregroundColor: AppColors.text,
            alignment: Alignment.centerLeft,
          ),
          child: Text(label, style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _brand(String title, List<String> steps) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accent)),
          const SizedBox(height: 8),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('•  $s',
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textDim)),
            ),
        ],
      ),
    );
  }
}
