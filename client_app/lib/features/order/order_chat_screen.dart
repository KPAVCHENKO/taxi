import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';

/// Небольшой чат пассажира с водителем на время заказа.
class OrderChatScreen extends ConsumerStatefulWidget {
  final int orderId;
  final String token;
  final String driverName;
  const OrderChatScreen({
    super.key,
    required this.orderId,
    required this.token,
    this.driverName = 'Водитель',
  });

  @override
  ConsumerState<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends ConsumerState<OrderChatScreen> {
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
    final list = await ref.read(apiProvider).chatGet(widget.orderId, widget.token, _lastId);
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
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    final ok = await ref.read(apiProvider).chatSend(widget.orderId, widget.token, text);
    if (mounted) setState(() => _sending = false);
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: Text('Чат · ${widget.driverName}')),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Напишите водителю — например, уточните адрес подачи',
                          textAlign: TextAlign.center, style: TextStyle(color: p.text2)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _msgs.length,
                    itemBuilder: (c, i) {
                      final m = _msgs[i];
                      final mine = m['sender'] == 'client';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints:
                              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: mine ? p.accent : p.surface2,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(m['body'].toString(),
                              style: TextStyle(color: mine ? Colors.white : p.text, fontSize: 15)),
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
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Сообщение…',
                        filled: true,
                        fillColor: p.surface2,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(backgroundColor: p.accent),
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
