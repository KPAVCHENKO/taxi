import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/order.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/chat_repository.dart';
import '../data/repositories/orders_repository.dart';

/// Глобальный navigatorKey — чтобы навигировать из push-обработчиков.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Куда пускать пользователя.
enum AuthStatus { unknown, loggedOut, needRegulations, loggedIn }

final authStatusProvider = StateProvider<AuthStatus>((_) => AuthStatus.unknown);

final authRepoProvider = Provider((_) => AuthRepository());
final ordersRepoProvider = Provider((_) => OrdersRepository());
final chatRepoProvider = Provider((_) => ChatRepository());

/// Активный входящий заказ (полноэкранный «звонок»). Ставит push-сервис/поллинг.
final incomingOrderProvider = StateProvider<TaxiOrder?>((_) => null);

/// id заказов, которые водитель «пропустил» в этой сессии (не звонить повторно).
final dismissedOrderIdsProvider = StateProvider<Set<int>>((_) => <int>{});
