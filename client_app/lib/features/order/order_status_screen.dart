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
    if (mounted && s != null) setState(() => _st = s);
  }

  Future<void> _call() async {
    final uri = Uri.parse('tel:${AppConfig.dispatcherPhone}');
    try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    final status = _st?.status ?? 'new';
    final stepData = _stepFor(status);

    return Scaffold(
      appBar: AppBar(title: const Text('Ваш заказ')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(width: 12, height: 12, decoration: const BoxDecoration(color: C.good, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.fromLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text))),
                ]),
                Padding(padding: const EdgeInsets.only(left: 5, top: 4, bottom: 4), child: Container(width: 2, height: 16, color: p.surface3)),
                Row(children: [
                  Container(width: 12, height: 12, decoration: const BoxDecoration(color: C.danger, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(widget.toLabel, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text))),
                ]),
                const SizedBox(height: 12),
                if ((_st?.price ?? widget.price) != null)
                  Text('${_st?.price ?? widget.price} ₽', style: heading(size: 24, color: p.text)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              children: [
                Text(stepData.$1, style: const TextStyle(fontSize: 44)),
                const SizedBox(height: 8),
                Text(stepData.$2, style: heading(size: 20, color: p.text), textAlign: TextAlign.center),
                if (status == 'accepted' && _st?.driverName != null) ...[
                  const SizedBox(height: 8),
                  Text(_st!.driverName!, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
                  if (_st?.carInfo != null) Text(_st!.carInfo!, style: TextStyle(color: p.text2)),
                ],
                if (status == 'new' && widget.noDriversOnline) ...[
                  const SizedBox(height: 10),
                  Text('Сейчас никто из водителей не на смене — диспетчер увидит заказ и перезвонит. Лучше также позвоните нам.',
                      textAlign: TextAlign.center, style: TextStyle(color: p.text2, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _call,
              icon: Icon(Icons.phone, color: p.accent),
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

  (String, String) _stepFor(String status) {
    switch (status) {
      case 'accepted':
        return ('✅', 'Водитель принял заказ');
      case 'completed':
        return ('🏁', 'Поездка завершена. Спасибо!');
      case 'cancelled':
        return ('❌', 'Заказ отменён');
      default:
        return ('🔎', 'Ищем водителя…');
    }
  }
}
