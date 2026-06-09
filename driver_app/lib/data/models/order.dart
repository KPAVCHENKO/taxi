/// Заказ. Приходит двумя путями: из REST `/driver/api/orders` (числа — числами,
/// даты — уже отформатированные строки) и из FCM data-payload (всё строками).
class TaxiOrder {
  final int id;
  final String fromAddress;
  final String toAddress;
  final String phone;
  final String payment; // cash | transfer
  final String rideType; // individual | shared
  final int? estimatedPrice;
  final String comment;
  final double? distanceKm;
  final int? durationMin;
  final String? scheduledAt; // отформатированная строка ('дд.мм ЧЧ:ММ') или ISO
  final String? createdAt;
  final bool intercity;
  final double? fromLat, fromLon, toLat, toLon;
  final bool arrived;

  const TaxiOrder({
    required this.id,
    required this.fromAddress,
    required this.toAddress,
    required this.phone,
    required this.payment,
    required this.rideType,
    this.estimatedPrice,
    this.comment = '',
    this.distanceKm,
    this.durationMin,
    this.scheduledAt,
    this.createdAt,
    this.intercity = false,
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
    this.arrived = false,
  });

  factory TaxiOrder.fromJson(Map<String, dynamic> j) {
    return TaxiOrder(
      id: _asInt(j['id']) ?? 0,
      fromAddress: (j['from_address'] ?? '').toString(),
      toAddress: (j['to_address'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      payment: (j['payment'] ?? 'cash').toString(),
      rideType: (j['ride_type'] ?? 'individual').toString(),
      estimatedPrice: _asInt(j['estimated_price']),
      comment: (j['comment'] ?? '').toString(),
      distanceKm: _asDouble(j['distance_km']),
      durationMin: _asInt(j['duration_min']),
      scheduledAt: _emptyToNull(j['scheduled_at']),
      createdAt: _emptyToNull(j['created_at']),
      intercity: j['intercity'] == true || j['intercity'] == 'true',
      fromLat: _asDouble(j['from_lat']), fromLon: _asDouble(j['from_lon']),
      toLat: _asDouble(j['to_lat']), toLon: _asDouble(j['to_lon']),
      arrived: j['arrived'] == true,
    );
  }

  /// Из FCM data-payload (все значения — строки).
  factory TaxiOrder.fromFcm(Map<String, dynamic> d) {
    return TaxiOrder(
      id: _asInt(d['order_id']) ?? 0,
      fromAddress: (d['from_address'] ?? '').toString(),
      toAddress: (d['to_address'] ?? '').toString(),
      phone: (d['phone'] ?? '').toString(),
      payment: (d['payment'] ?? 'cash').toString(),
      rideType: (d['ride_type'] ?? 'individual').toString(),
      estimatedPrice: _asInt(d['estimated_price']),
      comment: (d['comment'] ?? '').toString(),
      distanceKm: _asDouble(d['distance_km']),
      durationMin: _asInt(d['duration_min']),
      scheduledAt: _emptyToNull(d['scheduled_at']),
      createdAt: null,
      intercity: d['intercity'] == 'true' || d['intercity'] == true,
      fromLat: _asDouble(d['from_lat']), fromLon: _asDouble(d['from_lon']),
      toLat: _asDouble(d['to_lat']), toLon: _asDouble(d['to_lon']),
    );
  }

  Map<String, String> toFcmMap() => {
        'order_id': id.toString(),
        'from_address': fromAddress,
        'to_address': toAddress,
        'phone': phone,
        'payment': payment,
        'ride_type': rideType,
        'estimated_price': estimatedPrice?.toString() ?? '',
        'comment': comment,
        'distance_km': distanceKm?.toString() ?? '',
        'duration_min': durationMin?.toString() ?? '',
        'scheduled_at': scheduledAt ?? '',
        'intercity': intercity ? 'true' : 'false',
      };
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String? _emptyToNull(dynamic v) {
  final s = v?.toString() ?? '';
  return s.isEmpty ? null : s;
}
