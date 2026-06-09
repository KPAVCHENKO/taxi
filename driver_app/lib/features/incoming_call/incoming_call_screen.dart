import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../core/push/notifications.dart';
import '../../data/models/order.dart';
import '../../state/orders_controller.dart';
import '../../state/providers.dart';
import '../../widgets/order_card.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final TaxiOrder order;
  const IncomingCallScreen({super.key, required this.order});

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  late int _remaining;
  Timer? _timer;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _remaining = AppConfig.ringTimeoutSeconds;
    Notifications.instance.cancelIncoming();
    _startAlarm();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _remaining--);
      if (_remaining <= 0) _skip();
    });
  }

  Future<void> _startAlarm() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        // repeat: 0 — повторять весь паттерн с начала (непрерывно), пока не отменим
        Vibration.vibrate(pattern: [0, 600, 400, 600, 400, 800], repeat: 0);
      }
    } catch (_) {}
  }

  void _stopAlarm() {
    _timer?.cancel();
    try {
      Vibration.cancel();
    } catch (_) {}
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    _stopAlarm();
    final res = await ref.read(ordersControllerProvider.notifier).accept(widget.order.id);
    if (!mounted) return;
    if (res.ok) {
      _close();
    } else {
      final msg = res.status == 403
          ? 'Сначала выйдите на смену'
          : 'Заказ уже принят другим водителем';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      ref.read(ordersControllerProvider.notifier).dismissIncoming(widget.order.id);
      _close();
    }
  }

  void _skip() {
    _stopAlarm();
    ref.read(ordersControllerProvider.notifier).dismissIncoming(widget.order.id);
    _close();
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _stopAlarm();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // если заказ забрали/отменили извне — закрыть
    ref.listen<TaxiOrder?>(incomingOrderProvider, (prev, next) {
      if (next == null || next.id != widget.order.id) {
        _stopAlarm();
        _close();
      }
    });

    final progress = _remaining / AppConfig.ringTimeoutSeconds;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 8,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                        ),
                      ),
                      Text('$_remaining',
                          style: const TextStyle(
                              fontSize: 38, fontWeight: FontWeight.w800, color: AppColors.accent)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('🚖 Новый заказ',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: OrderCard(order: widget.order),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 64,
                        child: OutlinedButton(
                          onPressed: _accepting ? null : _skip,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textDim,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Пропустить', style: TextStyle(fontSize: 17)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: SizedBox(
                        height: 64,
                        child: ElevatedButton(
                          onPressed: _accepting ? null : _accept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: const Color(0xFF06281D),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _accepting
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Color(0xFF06281D)))
                              : const Text('✓ ПРИНЯТЬ',
                                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
