import 'order.dart';

/// Единый источник истины состояния водителя — из `GET /driver/api/orders`.
class OrdersState {
  final List<TaxiOrder> newOrders;
  final TaxiOrder? myOrder;
  final List<TaxiOrder> history;
  final int balance;
  final int todayEarnings;
  final int weekEarnings;
  final int monthEarnings;
  final int completedCount;
  final double? rating;
  final int ratingCount;
  final bool isOnline;
  final int chatUnreadGroup;
  final int chatUnreadDirect;

  const OrdersState({
    this.newOrders = const [],
    this.myOrder,
    this.history = const [],
    this.balance = 0,
    this.todayEarnings = 0,
    this.weekEarnings = 0,
    this.monthEarnings = 0,
    this.completedCount = 0,
    this.rating,
    this.ratingCount = 0,
    this.isOnline = false,
    this.chatUnreadGroup = 0,
    this.chatUnreadDirect = 0,
  });

  int get chatUnreadTotal => chatUnreadGroup + chatUnreadDirect;

  factory OrdersState.fromJson(Map<String, dynamic> j) {
    List<TaxiOrder> parseList(dynamic v) => (v as List? ?? [])
        .map((e) => TaxiOrder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    return OrdersState(
      newOrders: parseList(j['new_orders']),
      myOrder: j['my_order'] == null
          ? null
          : TaxiOrder.fromJson(Map<String, dynamic>.from(j['my_order'] as Map)),
      history: parseList(j['history']),
      balance: _i(j['balance']),
      todayEarnings: _i(j['today_earnings']),
      weekEarnings: _i(j['week_earnings']),
      monthEarnings: _i(j['month_earnings']),
      completedCount: _i(j['completed_count']),
      rating: (j['rating'] is num) ? (j['rating'] as num).toDouble() : null,
      ratingCount: _i(j['rating_count']),
      isOnline: j['is_online'] == true,
      chatUnreadGroup: _i(j['chat_unread_group']),
      chatUnreadDirect: _i(j['chat_unread_direct']),
    );
  }

  OrdersState copyWith({bool? isOnline}) => OrdersState(
        newOrders: newOrders,
        myOrder: myOrder,
        history: history,
        balance: balance,
        todayEarnings: todayEarnings,
        weekEarnings: weekEarnings,
        monthEarnings: monthEarnings,
        completedCount: completedCount,
        rating: rating,
        ratingCount: ratingCount,
        isOnline: isOnline ?? this.isOnline,
        chatUnreadGroup: chatUnreadGroup,
        chatUnreadDirect: chatUnreadDirect,
      );

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
