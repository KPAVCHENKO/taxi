import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../state/orders_controller.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(ordersControllerProvider).data.history;
    return Scaffold(
      appBar: AppBar(title: const Text('История поездок')),
      body: history.isEmpty
          ? const Center(
              child: Text('Пока нет завершённых заказов',
                  style: TextStyle(color: AppColors.textDim)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final o = history[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${o.fromAddress} → ${o.toAddress}',
                                style: const TextStyle(fontSize: 15, color: AppColors.text)),
                            const SizedBox(height: 4),
                            Text(o.createdAt ?? '',
                                style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(o.estimatedPrice != null ? '${o.estimatedPrice} ₽' : '—',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.green)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
