import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../data/models/models.dart';
import '../../state/providers.dart';
import '../../widgets/ui.dart';

class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key});

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  String _kind = 'Отзыв'; // Отзыв | Пожелание
  final _name = TextEditingController();
  final _text = TextEditingController();
  bool _busy = false;
  List<Review> _reviews = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ref.read(apiProvider).getReviews();
    if (mounted) setState(() => _reviews = list);
  }

  Future<void> _send() async {
    final name = _name.text.trim();
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Напишите текст')));
      return;
    }
    setState(() => _busy = true);
    final ok = await ref.read(apiProvider).sendReview(
          name: name.isEmpty ? 'Гость' : name,
          text: text,
          type: _kind == 'Пожелание' ? 'wish' : 'review',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _name.clear();
      _text.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Спасибо! Отправлено, появится после проверки.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Не удалось отправить')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Отзывы')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Оставить отзыв', style: heading(size: 18, color: p.text)),
                const SizedBox(height: 14),
                Segmented(options: const ['Отзыв', 'Пожелание'], value: _kind, onChanged: (v) => setState(() => _kind = v)),
                const SizedBox(height: 14),
                TextField(controller: _name, decoration: const InputDecoration(hintText: 'Ваше имя (необязательно)')),
                const SizedBox(height: 10),
                TextField(controller: _text, minLines: 2, maxLines: 5, decoration: InputDecoration(hintText: _kind == 'Пожелание' ? 'Что улучшить?' : 'Расскажите о поездке')),
                const SizedBox(height: 14),
                CtaButton(label: 'Отправить', busy: _busy, onPressed: _send),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_reviews.isNotEmpty)
            Text('Отзывы пассажиров', style: heading(size: 18, color: p.text)),
          const SizedBox(height: 10),
          for (final r in _reviews)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: TextStyle(fontWeight: FontWeight.w800, color: p.text)),
                    const SizedBox(height: 6),
                    Text(r.text, style: TextStyle(color: p.text2, height: 1.4)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
