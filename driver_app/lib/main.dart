import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/fgs/shift_service.dart';
import 'core/network/dio_client.dart';
import 'core/push/notifications.dart';
import 'core/push/push_service.dart';
import 'core/storage/prefs.dart';
import 'core/storage/token_storage.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Notifications.instance.init();
  await ShiftService.init();
  await Prefs.load();

  final container = ProviderContainer();

  // Разлогин по любому 401 из интерцептора.
  DioClient.instance.onUnauthorized = () {
    container.read(authStatusProvider.notifier).state = AuthStatus.loggedOut;
  };

  // Стартовый статус авторизации по наличию токена.
  final token = await TokenStorage.instance.getToken();
  final loggedIn = token != null && token.isNotEmpty;
  container.read(authStatusProvider.notifier).state =
      loggedIn ? AuthStatus.loggedIn : AuthStatus.loggedOut;

  gPush = PushService(container);
  if (loggedIn) {
    await gPush!.init();
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const DriverApp(),
  ));
}
