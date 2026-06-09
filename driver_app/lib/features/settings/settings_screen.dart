import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../core/storage/prefs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Звук и вибрация')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                SwitchListTile(
                  value: Prefs.sound,
                  activeColor: AppColors.accent,
                  title: const Text('Звук входящего заказа', style: TextStyle(color: AppColors.text, fontSize: 16)),
                  subtitle: const Text('Громкость — кнопками громкости телефона',
                      style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
                  onChanged: (v) async { await Prefs.setSound(v); setState(() {}); },
                ),
                const Divider(height: 1, color: Color(0x14FFFFFF)),
                SwitchListTile(
                  value: Prefs.vibration,
                  activeColor: AppColors.accent,
                  title: const Text('Вибрация', style: TextStyle(color: AppColors.text, fontSize: 16)),
                  onChanged: (v) async { await Prefs.setVibration(v); setState(() {}); },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Настройки применяются к следующему входящему заказу.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
        ],
      ),
    );
  }
}
