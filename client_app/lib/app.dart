import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'features/home/home_shell.dart';
import 'state/providers.dart';
import 'state/theme_provider.dart';

class ClientApp extends ConsumerWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // подтянуть тарифы (фолбэк уже есть)
    ref.watch(tariffsProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Казанское Такси',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3)),
          child: child!,
        );
      },
      home: const HomeShell(),
    );
  }
}
