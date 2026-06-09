import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/history.dart';
import '../../widgets/ui.dart';
import '../order/order_screen.dart';
import '../order/order_status_screen.dart';

class MyOrdersScreen extends ConsumerStatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  ConsumerState<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends ConsumerState<MyOrdersScreen> {
  List<MyOrder> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await History.load();
    if (mounted) setState(() { _orders = list; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Мои заказы')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Icon(Icons.receipt_long, size: 56, color: p.text3)),
                    const SizedBox(height: 12),
                    Center(child: Text('Здесь будут ваши заказы', style: TextStyle(color: p.text3, fontSize: 16))),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _orders.length,
                    itemBuilder: (c, i) {
                      final o = _orders[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => OrderStatusScreen(
                                      orderId: o.id, token: o.token,
                                      fromLabel: o.fromLabel, toLabel: o.toLabel, price: o.price,
                                    ),
                                  )),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${o.fromLabel} → ${o.toLabel}',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                                      const SizedBox(height: 4),
                                      Text(o.price != null ? '${o.price} ₽' : '—', style: TextStyle(color: p.text2)),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Повторить',
                                icon: Icon(Icons.refresh, color: p.accent),
                                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => OrderScreen(
                                    initialFrom: Settlements.byLabel(o.fromLabel),
                                    initialTo: Settlements.byLabel(o.toLabel),
                                  ),
                                )),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
