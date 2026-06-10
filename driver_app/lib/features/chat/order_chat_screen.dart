import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/repositories/orders_repository.dart';

/// Небольшой чат водителя с пассажиром по активному заказу.
class OrderChatScreen extends StatefulWidget {
  final int orderId;
  final String clientLabel;
  const OrderChatScreen({super.key, required this.orderId, this.clientLabel = 'Пассажир'});

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  final _repo = OrdersRepository();
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _msgs = [];
  int _lastId = 0;
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _repo.chatGet(widget.orderId, _lastId);
    if (!mounted || list.isEmpty) return;
    setState(() {
      _msgs.addAll(list);
      _lastId = (_msgs.last['id'] as num).toInt();
    });
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    final r = await _repo.chatSend(widget.orderId, t);
    if (mounted) setState(() => _sending = false);
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text('Чат · ${widget.clientLabel}')),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Напишите пассажиру — например, что подъезжаете',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _msgs.length,
                    itemBuilder: (c, i) {
                      final m = _msgs[i];
                      final mine = m['sender'] == 'driver';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints:
                              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: mine ? AppColors.accent : AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(m['body'].toString(),
                              style: TextStyle(
                                  color: mine ? Colors.black : AppColors.text, fontSize: 15)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: AppColors.text),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Сообщение…',
                        hintStyle: const TextStyle(color: AppColors.textFaint),
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send, color: Colors.black),
                    style: IconButton.styleFrom(backgroundColor: AppColors.accent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
