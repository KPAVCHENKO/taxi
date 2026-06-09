import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/config.dart';
import '../data/models/order.dart';
import '../data/models/orders_state.dart';
import '../data/repositories/orders_repository.dart';
import 'providers.dart';

class OrdersUi {
  final OrdersState data;
  final bool loading;
  final bool offline;
  final String? error;

  const OrdersUi({
    this.data = const OrdersState(),
    this.loading = false,
    this.offline = false,
    this.error,
  });

  OrdersUi copyWith({OrdersState? data, bool? loading, bool? offline, String? error}) =>
      OrdersUi(
        data: data ?? this.data,
        loading: loading ?? this.loading,
        offline: offline ?? this.offline,
        error: error,
      );
}

final ordersControllerProvider =
    StateNotifierProvider<OrdersController, OrdersUi>((ref) {
  return OrdersController(ref);
});

class OrdersController extends StateNotifier<OrdersUi> {
  OrdersController(this._ref) : super(const OrdersUi());

  final Ref _ref;
  OrdersRepository get _repo => _ref.read(ordersRepoProvider);

  Timer? _poll;
  Set<int> _seenNewIds = <int>{}; // чтобы не звонить повторно по тем же заказам
  bool _seenInitialized = false;

  // ── Поллинг ────────────────────────────────────────────────────────────────
  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(AppConfig.ordersPollForeground, (_) => refresh(silent: true));
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  // ── Загрузка ─────────────────────────────────────────────────────────────────
  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = state.copyWith(loading: true, error: null);
    try {
      final data = await _repo.fetch();
      state = state.copyWith(data: data, loading: false, offline: false, error: null);
      _detectIncoming(data);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 401 обрабатывает интерцептор (разлогин). Остальное — офлайн/ошибка.
      state = state.copyWith(
        loading: false,
        offline: code == null,
        error: code == null ? null : 'Ошибка загрузки',
      );
    } catch (_) {
      state = state.copyWith(loading: false, offline: true);
    }
  }

  /// Появился новый заказ, которого ещё не показывали → запустить «звонок».
  void _detectIncoming(OrdersState data) {
    final ids = data.newOrders.map((o) => o.id).toSet();
    if (!_seenInitialized) {
      _seenNewIds = ids;
      _seenInitialized = true;
      return;
    }
    if (!data.isOnline) {
      _seenNewIds = ids;
      return;
    }
    final dismissed = _ref.read(dismissedOrderIdsProvider);
    // если уже идёт звонок или есть активный заказ — не перебиваем
    final busy = _ref.read(incomingOrderProvider) != null || data.myOrder != null;
    TaxiOrder? fresh;
    for (final o in data.newOrders) {
      if (!_seenNewIds.contains(o.id) && !dismissed.contains(o.id)) {
        fresh = o;
        break;
      }
    }
    _seenNewIds = ids;
    if (fresh != null && !busy) {
      _ref.read(incomingOrderProvider.notifier).state = fresh;
    }
  }

  /// Внешний триггер из push (новый заказ пришёл pуш-ом раньше поллинга).
  void onPushNewOrder(TaxiOrder order) {
    if (_ref.read(dismissedOrderIdsProvider).contains(order.id)) return;
    final busy = _ref.read(incomingOrderProvider) != null || state.data.myOrder != null;
    if (!busy) {
      _ref.read(incomingOrderProvider.notifier).state = order;
    }
    refresh(silent: true);
  }

  /// Заказ забрали/отменили — закрыть звонок, если он про этот заказ.
  void onOrderGone(int orderId) {
    final cur = _ref.read(incomingOrderProvider);
    if (cur != null && cur.id == orderId) {
      _ref.read(incomingOrderProvider.notifier).state = null;
    }
    refresh(silent: true);
  }

  // ── Действия ─────────────────────────────────────────────────────────────────
  Future<ActionResult> toggleOnline(bool online) async {
    final r = await _repo.setOnline(online);
    if (r.ok) {
      state = state.copyWith(data: state.data.copyWith(isOnline: online));
      await refresh(silent: true);
    }
    return r;
  }

  Future<ActionResult> accept(int orderId) async {
    final r = await _repo.accept(orderId);
    if (r.ok) {
      _ref.read(incomingOrderProvider.notifier).state = null;
    }
    await refresh(silent: true);
    return r;
  }

  Future<ActionResult> complete(int orderId, int price) async {
    final r = await _repo.complete(orderId, price);
    await refresh(silent: true);
    return r;
  }

  Future<ActionResult> cancel(int orderId) async {
    final r = await _repo.cancel(orderId);
    await refresh(silent: true);
    return r;
  }

  void dismissIncoming(int orderId) {
    final s = {..._ref.read(dismissedOrderIdsProvider), orderId};
    _ref.read(dismissedOrderIdsProvider.notifier).state = s;
    final cur = _ref.read(incomingOrderProvider);
    if (cur != null && cur.id == orderId) {
      _ref.read(incomingOrderProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
