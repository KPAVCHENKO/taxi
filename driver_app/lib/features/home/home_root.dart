import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/fgs/shift_service.dart';
import '../../core/update/update_service.dart';
import '../../data/models/order.dart';
import '../../state/orders_controller.dart';
import '../../state/providers.dart';
import '../chat/chat_screen.dart';
import '../incoming_call/incoming_call_screen.dart';
import '../more/more_screen.dart';
import '../orders/orders_screen.dart';
import '../shift/shift_screen.dart';

class HomeRoot extends ConsumerStatefulWidget {
  const HomeRoot({super.key});

  @override
  ConsumerState<HomeRoot> createState() => _HomeRootState();
}

class _HomeRootState extends ConsumerState<HomeRoot> with WidgetsBindingObserver {
  int _tab = 0;
  bool _incomingShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final ctrl = ref.read(ordersControllerProvider.notifier);
    ctrl.refresh();
    ctrl.startPolling();
    ShiftService.onTick(() => ctrl.refresh(silent: true));
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (mounted) await runUpdateCheck(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(ordersControllerProvider.notifier).refresh(silent: true);
    }
  }

  void _handleIncoming(TaxiOrder? order) {
    if (order != null && !_incomingShown) {
      _incomingShown = true;
      Navigator.of(context)
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => IncomingCallScreen(order: order),
          ))
          .then((_) => _incomingShown = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // показ/скрытие экрана входящего заказа
    ref.listen<TaxiOrder?>(incomingOrderProvider, (prev, next) {
      // Экран входящего заказа сам закрывается, когда заказ исчезает; здесь только показ.
      _handleIncoming(next);
    });
    // на случай, если заказ уже стоит к моменту построения
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleIncoming(ref.read(incomingOrderProvider));
    });

    final ui = ref.watch(ordersControllerProvider);
    final unread = ui.data.chatUnreadTotal;

    return Scaffold(
      body: Column(
        children: [
          if (ui.offline) const _OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: const [
                ShiftScreen(),
                OrdersScreen(),
                ChatScreen(),
                MoreScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        height: 68,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Смена'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: ui.data.newOrders.isNotEmpty,
              label: Text('${ui.data.newOrders.length}'),
              child: const Icon(Icons.list_alt),
            ),
            label: 'Заказы',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            label: 'Чат',
          ),
          const NavigationDestination(icon: Icon(Icons.menu), label: 'Ещё'),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.red.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Text('Нет связи — показаны последние данные',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
    );
  }
}
