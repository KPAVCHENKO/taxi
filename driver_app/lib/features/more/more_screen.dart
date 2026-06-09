import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/fgs/shift_service.dart';
import '../../core/push/push_service.dart';
import '../../core/storage/token_storage.dart';
import '../../state/orders_controller.dart';
import '../../state/providers.dart';
import '../history/history_screen.dart';
import '../instructions/instructions_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(ordersControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _balanceCard(ui.data.balance, ui.data.todayEarnings, ui.data.completedCount),
          const SizedBox(height: 20),
          _tile(context, Icons.history, 'История поездок',
              () => _push(context, const HistoryScreen())),
          _tile(context, Icons.shield_outlined, 'Надёжная работа',
              () => _push(context, const InstructionsScreen())),
          const SizedBox(height: 20),
          const Text('Профиль', style: TextStyle(color: AppColors.textFaint)),
          const SizedBox(height: 8),
          FutureBuilder(
            future: Future.wait(
                [TokenStorage.instance.driverName, TokenStorage.instance.driverPhone]),
            builder: (ctx, snap) {
              final name = (snap.data != null) ? (snap.data![0] ?? '') : '';
              final phone = (snap.data != null) ? (snap.data![1] ?? '') : '';
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Водитель' : name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(phone, style: const TextStyle(color: AppColors.textDim)),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context, ref),
              icon: const Icon(Icons.logout, color: AppColors.red),
              label: const Text('Выйти', style: TextStyle(color: AppColors.red, fontSize: 16)),
              style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.red.withOpacity(0.4))),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('Казанское Такси · версия 1.0.0',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(int balance, int today, int completed) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _stat('$balance ₽', 'Баланс', AppColors.green),
          _stat('$today ₽', 'Сегодня', AppColors.accent),
          _stat('$completed', 'Поездок', AppColors.blue),
        ],
      ),
    );
  }

  Widget _stat(String v, String l, Color c) => Column(
        children: [
          Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 4),
          Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
        ],
      );

  Widget _tile(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.accent),
        title: Text(title, style: const TextStyle(fontSize: 16)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textFaint),
        onTap: onTap,
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Выйти из приложения?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(ordersControllerProvider.notifier).stopPolling();
    await ShiftService.stop();
    await gPush?.deleteToken();
    await TokenStorage.instance.clear();
    ref.read(authStatusProvider.notifier).state = AuthStatus.loggedOut;
  }
}
