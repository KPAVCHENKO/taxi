import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../data/models/order.dart';
import '../../state/orders_controller.dart';
import '../../widgets/order_card.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(ordersControllerProvider);
    final ctrl = ref.read(ordersControllerProvider.notifier);
    final orders = ui.data.newOrders;
    final online = ui.data.isOnline;

    return Scaffold(
      appBar: AppBar(title: const Text('Новые заказы')),
      body: RefreshIndicator(
        onRefresh: () => ctrl.refresh(),
        child: orders.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('😴', style: TextStyle(fontSize: 56))),
                  SizedBox(height: 12),
                  Center(
                      child: Text('Сейчас новых заказов нет',
                          style: TextStyle(fontSize: 17, color: AppColors.textDim))),
                ],
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!online)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Выйдите на смену, чтобы принимать заказы',
                        style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  for (final o in orders) ...[
                    OrderCard(
                      order: o,
                      trailing: SizedBox(
                        height: 56,
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: online ? AppColors.green : AppColors.surface2,
                            foregroundColor:
                                online ? const Color(0xFF06281D) : AppColors.textFaint,
                          ),
                          onPressed: online ? () => _accept(context, ref, o) : null,
                          child: const Text('✓ Принять заказ',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref, TaxiOrder o) async {
    final res = await ref.read(ordersControllerProvider.notifier).accept(o.id);
    if (!context.mounted) return;
    if (!res.ok) {
      final msg = res.status == 403
          ? 'Сначала выйдите на смену'
          : res.status == 409
              ? 'Заказ уже принят другим водителем'
              : 'Не удалось принять заказ';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
