import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/api.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

final apiProvider = Provider((_) => Api());

/// Загрузка тарифов с сервера (фолбэк уже зашит).
final tariffsProvider = FutureProvider<void>((ref) async {
  await ref.read(apiProvider).loadTariffs();
});
