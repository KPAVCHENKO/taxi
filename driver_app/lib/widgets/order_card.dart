import 'package:flutter/material.dart';

import '../config/config.dart';
import '../config/theme.dart';
import '../data/models/order.dart';

/// Крупная карточка маршрута заказа. Используется в ленте, «Мой заказ», звонке.
class OrderCard extends StatelessWidget {
  final TaxiOrder order;
  final Widget? trailing;
  final bool showPhone;

  const OrderCard({
    super.key,
    required this.order,
    this.trailing,
    this.showPhone = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (order.intercity)
                _badge('🛣 Межгород', AppColors.blue)
              else
                _badge('📍 По району', AppColors.green),
              if (Labels.rideType(order.rideType) == 'Попутно')
                _badge('👥 Попутно', AppColors.accent),
              if (Labels.payment(order.payment) == 'Перевод')
                _badge('💳 Перевод', AppColors.blue),
              if (order.scheduledAt != null)
                _badge('🗓 ${order.scheduledAt}', AppColors.accent),
              if (order.createdAt != null)
                _badge('🕐 ${order.createdAt}', AppColors.textFaint),
            ],
          ),
          const SizedBox(height: 14),
          _routeRow(AppColors.green, order.fromAddress),
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(width: 2, height: 18, color: AppColors.border),
          ),
          _routeRow(AppColors.red, order.toAddress),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (order.estimatedPrice != null)
                Text('${order.estimatedPrice} ₽',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.green)),
              if (order.distanceKm != null)
                _meta('📏 ${order.distanceKm!.toStringAsFixed(1)} км'),
              if (order.durationMin != null) _meta('⏱ ~${order.durationMin} мин'),
              _meta('💵 ${Labels.payment(order.payment)}'),
            ],
          ),
          if (showPhone && order.phone.isNotEmpty) ...[
            const SizedBox(height: 8),
            _meta('📞 ${order.phone}'),
          ],
          if (order.comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('💬 ${order.comment}',
                  style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 15)),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(height: 16),
            trailing!,
          ],
        ],
      ),
    );
  }

  Widget _routeRow(Color dot, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
      ],
    );
  }

  Widget _meta(String t) =>
      Text(t, style: const TextStyle(fontSize: 15, color: AppColors.textDim));

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: c.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t, style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w700)),
      );
}
