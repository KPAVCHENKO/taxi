import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../core/push/push_service.dart';
import '../../data/models/models.dart';
import '../../state/providers.dart';
import '../../widgets/ui.dart';

class OrderStatusScreen extends ConsumerStatefulWidget {
  final int orderId;
  final String token;
  final String fromLabel;
  final String toLabel;
  final int? price;
  final bool noDriversOnline;

  const OrderStatusScreen({
    super.key,
    required this.orderId,
    required this.token,
    required this.fromLabel,
    required this.toLabel,
    this.price,
    this.noDriversOnline = false,
  });

  @override
  ConsumerState<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends ConsumerState<OrderStatusScreen> {
  OrderStatus? _st;
  Timer? _poll;
  bool _cancelling = false;
  int? _myRating; // что поставил локально

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(AppConfig.statusPoll, (_) => _refresh());
    PushService.instance.onStatusMessage = (_) => _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    PushService.instance.onStatusMessage = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    final s = await ref.read(apiProvider).getStatus(widget.orderId, widget.token);
    if (mounted && s != null) {
      setState(() {
        _st = s;
        _myRating ??= s.rating;
      });
    }
  }

  Future<void> _callPhone(String phone) async {
    try {
      await launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette(ctx).surface,
        title: const Text('Отменить заказ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отменить')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cancelling = true);
    final done = await ref.read(apiProvider).cancel(widget.orderId, widget.token);
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (done) _refresh();
  }

  Future<void> _rate(int stars) async {
    setState(() => _myRating = stars);
    final ok = await ref.read(apiProvider).rate(widget.orderId, widget.token, stars);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить оценку')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    final st = _st;
    final status = st?.status ?? 'new';
    final step = _stepFor(status, st);

    return Scaffold(
      appBar: AppBar(title: const Text('Ваш заказ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _routeRow(C.good, widget.fromLabel, p),
                Padding(padding: const EdgeInsets.only(left: 5, top: 4, bottom: 4), child: Container(width: 2, height: 16, color: p.surface3)),
                _routeRow(C.danger, widget.toLabel, p),
                if ((st?.price ?? widget.price) != null) ...[
                  const SizedBox(height: 12),
                  Text('${st?.price ?? widget.price} ₽', style: heading(size: 24, color: p.text)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                Text(step.$1, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text(step.$2, style: heading(size: 20, color: p.text), textAlign: TextAlign.center),
                if (status == 'accepted' && st?.driverName != null) ...[
                  const SizedBox(height: 10),
                  Text(st!.driverName!, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.text)),
                  if (st.carInfo != null) Text(st.carInfo!, style: TextStyle(color: p.text2)),
                  if (st.driverRating != null)
                    Padding(padding: const EdgeInsets.only(top: 2), child: Text('⭐ ${st.driverRating}', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700))),
                  if (st.driverPhone != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 50,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _callPhone(st.driverPhone!),
                        icon: Icon(Icons.phone, color: C.good),
                        label: const Text('Позвонить водителю', style: TextStyle(fontSize: 16, color: C.good)),
                        style: OutlinedButton.styleFrom(side: BorderSide(color: C.good.withValues(alpha: 0.5))),
                      ),
                    ),
                  ],
                ],
                if (status == 'new' && widget.noDriversOnline) ...[
                  const SizedBox(height: 10),
                  Text('Сейчас никто из водителей не на смене — диспетчер увидит заказ и перезвонит. Лучше также позвоните нам.',
                      textAlign: TextAlign.center, style: TextStyle(color: p.text2, fontSize: 13)),
                ],
              ],
            ),
          ),

          // Оценка завершённой поездки
          if (status == 'completed') ...[
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                children: [
                  Text(_myRating == null ? 'Оцените поездку' : 'Спасибо за оценку!',
                      style: heading(size: 18, color: p.text)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int s = 1; s <= 5; s++)
                        IconButton(
                          iconSize: 38,
                          onPressed: _myRating == null ? () => _rate(s) : null,
                          icon: Icon(
                            (_myRating ?? 0) >= s ? Icons.star : Icons.star_border,
                            color: p.accent,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _callPhone(AppConfig.dispatcherPhone),
              icon: Icon(Icons.support_agent, color: p.accent),
              label: Text('Позвонить диспетчеру', style: TextStyle(color: p.accent, fontSize: 16)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: p.accent.withValues(alpha: 0.5))),
            ),
          ),
          const SizedBox(height: 10),
          if (status == 'new' || status == 'accepted')
            SizedBox(
              height: 52,
              child: TextButton(
                onPressed: _cancelling ? null : _cancel,
                child: _cancelling
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.danger))
                    : const Text('Отменить заказ', style: TextStyle(color: C.danger, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _routeRow(Color dot, String text, AppPalette p) => Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text))),
        ],
      );

  (String, String) _stepFor(String status, OrderStatus? st) {
    switch (status) {
      case 'accepted':
        return st?.arrived == true ? ('🚗', 'Водитель на месте') : ('✅', 'Водитель принял заказ');
      case 'completed':
        return ('🏁', 'Поездка завершена');
      case 'cancelled':
        return ('❌', 'Заказ отменён');
      default:
        return ('🔎', 'Ищем водителя…');
    }
  }
}
