import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../state/providers.dart';

class RegulationsScreen extends ConsumerStatefulWidget {
  const RegulationsScreen({super.key});

  @override
  ConsumerState<RegulationsScreen> createState() => _RegulationsScreenState();
}

class _RegulationsScreenState extends ConsumerState<RegulationsScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(authRepoProvider).acceptRegulations();
    if (!mounted) return;
    if (ok) {
      ref.read(authStatusProvider.notifier).state = AuthStatus.loggedIn;
    } else {
      setState(() {
        _busy = false;
        _error = 'Не удалось подтвердить. Попробуйте ещё раз или обратитесь к диспетчеру.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Регламент')),
      body: SafeArea(
        child: Column(
          children: [
            const Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Правила работы водителя «Казанское Такси»\n\n'
                  '1. Выходите на смену, когда готовы принимать заказы.\n'
                  '2. Принимайте заказ, только если можете его выполнить.\n'
                  '3. Будьте вежливы с пассажирами.\n'
                  '4. Итоговую стоимость поездки определяет тариф сервиса.\n'
                  '5. При проблемах пишите диспетчеру в чат.\n\n'
                  'Нажимая «Принимаю», вы соглашаетесь с правилами.',
                  style: TextStyle(fontSize: 17, height: 1.6, color: AppColors.text),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_error!, style: const TextStyle(color: AppColors.red)),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: _busy ? null : _accept,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Color(0xFF0F1117)))
                    : const Text('Принимаю'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
