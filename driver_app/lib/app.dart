import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_root.dart';
import 'features/regulations/regulations_screen.dart';
import 'features/splash/splash_screen.dart';
import 'state/providers.dart';

class DriverApp extends ConsumerWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authStatusProvider);
    return MaterialApp(
      title: 'Казанское Такси — Водитель',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.dark,
      // фиксируем масштаб, но не даём ломать вёрстку при крупном системном шрифте
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3);
        return MediaQuery(data: mq.copyWith(textScaler: clamped), child: child!);
      },
      home: switch (status) {
        AuthStatus.unknown => const SplashScreen(),
        AuthStatus.loggedOut => const LoginScreen(),
        AuthStatus.needRegulations => const RegulationsScreen(),
        AuthStatus.loggedIn => const HomeRoot(),
      },
    );
  }
}
