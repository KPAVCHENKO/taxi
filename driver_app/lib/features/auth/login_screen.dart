import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/push/push_service.dart';
import '../../state/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final phone = _phone.text.trim();
    final pin = _pin.text.trim();
    if (phone.length < 10) {
      setState(() => _error = 'Введите номер телефона');
      return;
    }
    if (pin.isEmpty) {
      setState(() => _error = 'Введите PIN');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref.read(authRepoProvider).login(phone, pin);
    if (!mounted) return;
    if (res.ok) {
      await gPush?.init();
      ref.read(authStatusProvider.notifier).state =
          res.regulationsAccepted ? AuthStatus.loggedIn : AuthStatus.needRegulations;
    } else {
      setState(() {
        _busy = false;
        _error = res.error ?? 'Неверный телефон или PIN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('🚖', style: TextStyle(fontSize: 56), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text('Казанское Такси',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Приложение водителя',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                const SizedBox(height: 36),
                const Text('Телефон', style: TextStyle(color: AppColors.textDim)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 20, letterSpacing: 1),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'))],
                  decoration: const InputDecoration(hintText: '+7 ___ ___-__-__'),
                ),
                const SizedBox(height: 18),
                const Text('PIN-код', style: TextStyle(color: AppColors.textDim)),
                const SizedBox(height: 8),
                TextField(
                  controller: _pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  style: const TextStyle(fontSize: 20, letterSpacing: 4),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '••••'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.red, fontSize: 15)),
                  ),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Color(0xFF0F1117)))
                      : const Text('Войти'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Телефон и PIN выдаёт диспетчер',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
