import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/config.dart';
import '../../config/tariffs.dart';
import '../../config/theme.dart';
import '../../core/push/push_service.dart';
import '../../data/models/models.dart';
import '../../data/repositories/favorites.dart';
import '../../data/repositories/history.dart';
import '../../state/providers.dart';
import '../../widgets/ui.dart';
import '../map/map_picker_screen.dart';
import 'order_status_screen.dart';

class OrderScreen extends ConsumerStatefulWidget {
  final Settle? initialFrom;
  final Settle? initialTo;
  const OrderScreen({super.key, this.initialFrom, this.initialTo});

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Place? _from;
  Place? _to;
  final _fromDetail = TextEditingController();
  final _toDetail = TextEditingController();
  final _comment = TextEditingController();
  final _phone = TextEditingController();

  String _when = 'Сейчас';
  DateTime? _scheduledAt;
  String _type = 'Индивидуально';
  String _pay = 'Наличные';
  bool _consent = false;
  bool _forOther = false;
  bool _busy = false;
  String? _error;
  List<FavPlace> _favs = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialFrom != null) {
      _from = Place(address: widget.initialFrom!.label, key: widget.initialFrom!.key);
    }
    if (widget.initialTo != null) {
      _to = Place(address: widget.initialTo!.label, key: widget.initialTo!.key);
    }
    _loadFavs();
  }

  Future<void> _loadFavs() async {
    final f = await Favorites.load();
    if (mounted) setState(() => _favs = f);
  }

  void _useFav(FavPlace f) {
    final pl = Place(address: f.address, key: f.key, lat: f.lat, lon: f.lon);
    setState(() {
      if (_from == null) { _from = pl; } else { _to = pl; }
    });
  }

  Future<void> _addFav() async {
    final s = await pickSettlement(context, 'Сохранить адрес');
    if (s == null || !mounted) return;
    final ctrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette(ctx).surface,
        title: const Text('Название'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Дом, Работа…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    await Favorites.add(FavPlace(label: label, address: s.label, key: s.key));
    _loadFavs();
  }

  Future<void> _delFav(int i) async {
    await Favorites.removeAt(i);
    _loadFavs();
  }

  @override
  void dispose() {
    _fromDetail.dispose();
    _toDetail.dispose();
    _comment.dispose();
    _phone.dispose();
    super.dispose();
  }

  int? get _price => Tariffs.price(_from?.key, _to?.key);

  String _compose(Place? pl, TextEditingController detail) {
    if (pl == null) return '';
    final d = detail.text.trim();
    return d.isEmpty ? pl.address : '${pl.address}, $d';
  }

  Future<void> _pickList(bool isFrom) async {
    final s = await pickSettlement(context, isFrom ? 'Откуда едем' : 'Куда едем');
    if (s == null) return;
    setState(() {
      final pl = Place(address: s.label, key: s.key);
      if (isFrom) { _from = pl; } else { _to = pl; }
    });
  }

  Future<void> _pickMap(bool isFrom) async {
    final pl = await Navigator.of(context).push<Place>(MaterialPageRoute(
      builder: (_) => MapPickerScreen(title: isFrom ? 'Откуда' : 'Куда'),
    ));
    if (pl == null) return;
    setState(() {
      final withKey = Place(address: pl.address, key: Tariffs.matchKey(pl.address), lat: pl.lat, lon: pl.lon);
      if (isFrom) { _from = withKey; } else { _to = withKey; }
    });
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 14)), initialDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 30))));
    if (time == null) return;
    setState(() {
      _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _when = 'Ко времени';
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_from == null) { setState(() => _error = 'Выберите, откуда ехать'); return; }
    if (_to == null) { setState(() => _error = 'Выберите, куда ехать'); return; }
    if (_from!.key != null && _from!.key == _to!.key) { setState(() => _error = 'Откуда и куда совпадают'); return; }
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) { setState(() => _error = 'Введите номер телефона'); return; }
    if (!_consent) { setState(() => _error = 'Подтвердите согласие на обработку данных'); return; }

    setState(() { _busy = true; _error = null; });

    final body = <String, dynamic>{
      'phone': _phone.text.trim(),
      'from_address': _compose(_from, _fromDetail),
      'to_address': _compose(_to, _toDetail),
      'from_lat': _from!.lat,
      'from_lon': _from!.lon,
      'to_lat': _to!.lat,
      'to_lon': _to!.lon,
      'comment': _comment.text.trim(),
      'payment': _pay == 'Перевод' ? 'transfer' : 'cash',
      'ride_type': _type == 'Попутно' ? 'shared' : 'individual',
      'estimated_price': _price,
      'fcm_token': await PushService.instance.ensureToken(),
    };
    if (_when == 'Ко времени' && _scheduledAt != null) {
      body['scheduled_at'] = _scheduledAt!.subtract(const Duration(hours: 5)).toIso8601String();
    }

    final res = await ref.read(apiProvider).createOrder(body);
    if (!mounted) return;
    if (res.ok && res.orderId != null && res.token != null) {
      await History.add(MyOrder(
        id: res.orderId!, token: res.token!,
        fromLabel: _from!.address, toLabel: _to!.address,
        price: _price, ts: DateTime.now().millisecondsSinceEpoch,
      ));
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OrderStatusScreen(
          orderId: res.orderId!, token: res.token!,
          fromLabel: _from!.address, toLabel: _to!.address,
          price: _price, noDriversOnline: res.noDriversOnline,
        ),
      ));
      setState(() { _busy = false; });
    } else {
      setState(() { _busy = false; _error = res.error ?? 'Не удалось оформить заказ'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Заказать такси')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _favRow(p),
          AppCard(
            child: Column(
              children: [
                _placeRow(label: 'ОТКУДА', place: _from, dot: C.good, isFrom: true),
                const SizedBox(height: 8),
                TextField(controller: _fromDetail, decoration: const InputDecoration(hintText: 'Точный адрес / ориентир (необязательно)')),
                const SizedBox(height: 16),
                _placeRow(label: 'КУДА', place: _to, dot: C.danger, isFrom: false),
                const SizedBox(height: 8),
                TextField(controller: _toDetail, decoration: const InputDecoration(hintText: 'Точный адрес / ориентир (необязательно)')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _priceCard(p),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('Когда', p),
                Segmented(options: const ['Сейчас', 'Ко времени'], value: _when, onChanged: (v) {
                  if (v == 'Ко времени') { _pickWhen(); } else { setState(() { _when = 'Сейчас'; _scheduledAt = null; }); }
                }),
                if (_when == 'Ко времени' && _scheduledAt != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(
                    'На ${_scheduledAt!.day.toString().padLeft(2,'0')}.${_scheduledAt!.month.toString().padLeft(2,'0')} '
                    '${_scheduledAt!.hour.toString().padLeft(2,'0')}:${_scheduledAt!.minute.toString().padLeft(2,'0')}',
                    style: TextStyle(color: p.text2))),
                const SizedBox(height: 16),
                _label('Тип поездки', p),
                Segmented(options: const ['Индивидуально', 'Попутно'], value: _type, onChanged: (v) => setState(() => _type = v)),
                const SizedBox(height: 16),
                _label('Оплата', p),
                Segmented(options: const ['Наличные', 'Перевод'], value: _pay, onChanged: (v) => setState(() => _pay = v)),
                const SizedBox(height: 16),
                _label('Комментарий', p),
                TextField(controller: _comment, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'Например: подъезд 2, позвонить заранее')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _forOther = !_forOther),
                  child: Row(children: [
                    Icon(_forOther ? Icons.check_box : Icons.check_box_outline_blank,
                        color: _forOther ? p.accent : p.text3, size: 22),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Заказываю не себе — укажу телефон пассажира',
                        style: TextStyle(color: p.text2, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 12),
                _label(_forOther ? 'Телефон пассажира' : 'Ваш телефон', p),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ()]'))],
                  style: const TextStyle(fontSize: 18),
                  decoration: const InputDecoration(hintText: '+7 (___) ___-__-__'),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () => setState(() => _consent = !_consent),
                  child: Row(children: [
                    Icon(_consent ? Icons.check_box : Icons.check_box_outline_blank, color: _consent ? p.accent : p.text3),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Согласен на обработку персональных данных', style: TextStyle(color: p.text2, fontSize: 13))),
                  ]),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: C.danger)),
            ),
          ],
          const SizedBox(height: 18),
          CtaButton(label: 'Заказать такси', busy: _busy, onPressed: _submit),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _favRow(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (int i = 0; i < _favs.length; i++) ...[
              GestureDetector(
                onTap: () => _useFav(_favs[i]),
                onLongPress: () => _delFav(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.surface3),
                  ),
                  child: Row(children: [
                    Icon(Icons.star, size: 16, color: p.accent),
                    const SizedBox(width: 6),
                    Text(_favs[i].label, style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ],
            GestureDetector(
              onTap: _addFav,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Icon(Icons.add, size: 16, color: p.accent),
                  const SizedBox(width: 4),
                  Text('Адрес', style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeRow({required String label, required Place? place, required Color dot, required bool isFrom}) {
    final p = palette(context);
    return Row(
      children: [
        Expanded(child: SettlePicker(label: label, display: place?.address, dotColor: dot, onTap: () => _pickList(isFrom))),
        const SizedBox(width: 8),
        SizedBox(
          width: 52, height: 58,
          child: ElevatedButton(
            onPressed: () => _pickMap(isFrom),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: p.surface2,
              foregroundColor: p.accent,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Icon(Icons.map_outlined),
          ),
        ),
      ],
    );
  }

  Widget _label(String t, AppPalette p) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.text3)),
      );

  Widget _priceCard(AppPalette p) {
    final price = _price;
    final ready = _from != null && _to != null;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('СТОИМОСТЬ', style: TextStyle(fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.w700, color: p.text3)),
                const SizedBox(height: 6),
                if (!ready)
                  Text('Выберите маршрут', style: TextStyle(fontSize: 18, color: p.text3))
                else if (price == null)
                  Text('Уточнит диспетчер', style: heading(size: 22, color: p.text))
                else
                  Text('$price ₽', style: heading(size: 30, color: p.text)),
                if (ready && price != null && _type == 'Попутно')
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text('попутно — дешевле', style: TextStyle(color: C.good, fontWeight: FontWeight.w600, fontSize: 12))),
              ],
            ),
          ),
          Icon(Icons.local_taxi, color: p.accent, size: 40),
        ],
      ),
    );
  }
}
