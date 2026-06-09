import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../data/models/chat_message.dart';
import '../../state/orders_controller.dart';
import '../../state/providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  String _room = 'group'; // group | direct
  final List<ChatMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  int _lastId = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _switchRoom('group');
    _poll = Timer.periodic(AppConfig.chatPoll, (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _switchRoom(String room) {
    setState(() {
      _room = room;
      _messages.clear();
      _lastId = 0;
      _loading = true;
    });
    _load();
    ref.read(chatRepoProvider).seen(room);
  }

  Future<void> _load() async {
    try {
      final msgs = await ref.read(chatRepoProvider).fetch(_room, after: _lastId);
      if (!mounted) return;
      if (msgs.isNotEmpty) {
        setState(() {
          _messages.addAll(msgs);
          _lastId = _messages.last.id;
        });
        ref.read(chatRepoProvider).seen(_room);
        ref.read(ordersControllerProvider.notifier).refresh(silent: true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      }
    } catch (_) {}
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _toBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final ok = await ref.read(chatRepoProvider).send(_room, text);
    if (ok) {
      await _load();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Не отправлено — нет связи')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат с диспетчером'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _tab('Общий', 'group'),
                const SizedBox(width: 8),
                _tab('Личный', 'direct'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _messages.isEmpty
                    ? const Center(
                        child: Text('Сообщений пока нет',
                            style: TextStyle(color: AppColors.textDim)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, i) => _bubble(_messages[i]),
                      ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _tab(String label, String room) {
    final active = _room == room;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchRoom(room),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent.withOpacity(0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? AppColors.accent : AppColors.border),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: active ? AppColors.accent : AppColors.textDim,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? AppColors.green.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(m.authorName,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.blue, fontWeight: FontWeight.w700)),
            Text(m.body, style: const TextStyle(fontSize: 16, color: AppColors.text)),
            const SizedBox(height: 2),
            Text(m.createdAt,
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(hintText: 'Сообщение…'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              width: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.accent,
                ),
                onPressed: _send,
                child: const Icon(Icons.send, color: Color(0xFF0F1117)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
