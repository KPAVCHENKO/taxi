/// Локальная запись заказа (история на устройстве).
class MyOrder {
  final int id;
  final String token;
  final String fromLabel;
  final String toLabel;
  final int? price;
  final int ts; // когда создан (ms)

  const MyOrder({
    required this.id,
    required this.token,
    required this.fromLabel,
    required this.toLabel,
    this.price,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'id': id, 'token': token, 'from': fromLabel, 'to': toLabel,
        'price': price, 'ts': ts,
      };

  factory MyOrder.fromJson(Map<String, dynamic> j) => MyOrder(
        id: j['id'] as int,
        token: j['token'].toString(),
        fromLabel: (j['from'] ?? '').toString(),
        toLabel: (j['to'] ?? '').toString(),
        price: j['price'] is int ? j['price'] as int : int.tryParse('${j['price']}'),
        ts: j['ts'] is int ? j['ts'] as int : 0,
      );
}

/// Статус заказа с сервера.
class OrderStatus {
  final String status; // new | accepted | completed | cancelled
  final String statusLabel;
  final String? driverName;
  final String? driverPhone;
  final double? driverRating;
  final String? carInfo;
  final bool arrived;
  final int? rating; // оценка пассажира, если уже поставлена
  final int? price;
  final String fromAddress;
  final String toAddress;

  const OrderStatus({
    required this.status,
    required this.statusLabel,
    this.driverName,
    this.driverPhone,
    this.driverRating,
    this.carInfo,
    this.arrived = false,
    this.rating,
    this.price,
    this.fromAddress = '',
    this.toAddress = '',
  });

  factory OrderStatus.fromJson(Map<String, dynamic> j) => OrderStatus(
        status: (j['status'] ?? 'new').toString(),
        statusLabel: (j['status_label'] ?? '').toString(),
        driverName: _s(j['driver_name']),
        driverPhone: _s(j['driver_phone']),
        driverRating: (j['driver_rating'] is num) ? (j['driver_rating'] as num).toDouble() : null,
        carInfo: _s(j['car_info']),
        arrived: j['arrived'] == true,
        rating: j['rating'] is int ? j['rating'] as int : int.tryParse('${j['rating']}'),
        price: j['price'] is int ? j['price'] as int : int.tryParse('${j['price']}'),
        fromAddress: (j['from_address'] ?? '').toString(),
        toAddress: (j['to_address'] ?? '').toString(),
      );

  static String? _s(dynamic v) {
    final s = v?.toString() ?? '';
    return s.isEmpty || s == 'null' ? null : s;
  }
}

/// Отзыв.
class Review {
  final String name;
  final String text;
  const Review(this.name, this.text);
}

/// Точка маршрута: адрес (для отображения и заказа) + ключ населённого пункта
/// (для расчёта цены) + координаты (если выбрано на карте).
class Place {
  final String address;
  final String? key;
  final double? lat;
  final double? lon;
  const Place({required this.address, this.key, this.lat, this.lon});
}
