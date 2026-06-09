import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../core/fgs/shift_service.dart';
import '../../data/models/order.dart';
import '../../state/orders_controller.dart';
import '../../widgets/order_card.dart';

class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(ordersControllerProvider);
    final ctrl = ref.read(ordersControllerProvider.notifier);
    final online = ui.data.isOnline;

    return Scaffold(
      appBar: AppBar(title: const Text('Смена')),
      body: RefreshIndicator(
        onRefresh: () => ctrl.refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusBanner(online),
            const SizedBox(height: 16),
            _toggleButton(context, ref, online),
            const SizedBox(height: 20),
            _summary(ui.data.todayEarnings, ui.data.completedCount, ui.data.balance),
            if (ui.data.myOrder != null) ...[
              const SizedBox(height: 24),
              const Text('Активный заказ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _ActiveOrder(order: ui.data.myOrder!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(bool online) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (online ? AppColors.green : AppColors.red).withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (online ? AppColors.green : AppColors.red).withOpacity(0.3)),
      ),
      child: Text(
        online
            ? '🟢 Вы на смене — заказы приходят'
            : '⚫ Вы не на смене — заказы НЕ приходят',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: online ? AppColors.green : AppColors.red,
        ),
      ),
    );
  }

  Widget _toggleButton(BuildContext context, WidgetRef ref, bool online) {
    return SizedBox(
      height: 72,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: online ? AppColors.surface2 : AppColors.green,
          foregroundColor: online ? AppColors.textDim : const Color(0xFF06281D),
        ),
        onPressed: () async {
          final ctrl = ref.read(ordersControllerProvider.notifier);
          final res = await ctrl.toggleOnline(!online);
          if (res.ok) {
            if (!online) {
              await ShiftService.start();
            } else {
              await ShiftService.stop();
            }
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Не удалось переключить смену')));
          }
        },
        child: Text(
          online ? 'ЗАВЕРШИТЬ СМЕНУ' : '🟢 ВЫЙТИ НА СМЕНУ',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _summary(int today, int completed, int balance) {
    Widget cell(String val, String label, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(val,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell('$today ₽', 'Сегодня', AppColors.accent),
        cell('$completed', 'Выполнено', AppColors.blue),
        cell('$balance ₽', 'Баланс', AppColors.green),
      ],
    );
  }
}

class _ActiveOrder extends ConsumerWidget {
  final TaxiOrder order;
  const _ActiveOrder({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OrderCard(
      order: order,
      trailing: Column(
        children: [
          SizedBox(
            height: 56,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _call(order.phone),
              icon: const Icon(Icons.phone, color: AppColors.green),
              label: const Text('Позвонить пассажиру',
                  style: TextStyle(fontSize: 17, color: AppColors.green)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.green.withOpacity(0.4)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 7,
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green,
                        foregroundColor: const Color(0xFF06281D)),
                    onPressed: () => _completeSheet(context, ref),
                    child: const Text('✅ Завершить',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () => _cancel(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: BorderSide(color: AppColors.red.withOpacity(0.4)),
                    ),
                    child: const Text('Отмена'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _completeSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CompleteSheet(order: order),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Отменить заказ?'),
        content: const Text('Заказ вернётся диспетчеру.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(ordersControllerProvider.notifier).cancel(order.id);
    }
  }
}

class _CompleteSheet extends ConsumerStatefulWidget {
  final TaxiOrder order;
  const _CompleteSheet({required this.order});

  @override
  ConsumerState<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends ConsumerState<_CompleteSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final price = widget.order.estimatedPrice ?? 0;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✅ Завершить поездку',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const Text('Стоимость поездки (по тарифу)',
              style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$price ₽',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.green)),
          ),
          const SizedBox(height: 8),
          const Text('Итоговую цену подтверждает сервис по тарифу',
              style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final res = await ref
                          .read(ordersControllerProvider.notifier)
                          .complete(widget.order.id, price);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      if (!res.ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Не удалось завершить, попробуйте ещё раз')));
                      }
                    },
              child: _busy
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF0F1117)))
                  : const Text('Завершить и получить деньги'),
            ),
          ),
        ],
      ),
    );
  }
}
