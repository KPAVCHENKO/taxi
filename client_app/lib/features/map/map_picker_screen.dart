import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/config.dart';
import '../../config/theme.dart';
import '../../data/models/models.dart';

/// Выбор точки на карте Яндекса (страница /map-picker во WebView).
class MapPickerScreen extends StatefulWidget {
  final String title;
  const MapPickerScreen({super.key, required this.title});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late final WebViewController _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) { if (mounted) setState(() => _loading = false); },
      ))
      ..addJavaScriptChannel('FlutterPicker', onMessageReceived: (m) {
        try {
          final d = jsonDecode(m.message) as Map<String, dynamic>;
          final place = Place(
            address: (d['address'] ?? '').toString(),
            lat: (d['lat'] as num?)?.toDouble(),
            lon: (d['lon'] as num?)?.toDouble(),
          );
          if (mounted && place.address.isNotEmpty) Navigator.of(context).pop(place);
        } catch (_) {}
      })
      ..loadRequest(Uri.parse('${AppConfig.baseUrl}/map-picker'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          WebViewWidget(controller: _c),
          if (_loading) Center(child: CircularProgressIndicator(color: palette(context).accent)),
        ],
      ),
    );
  }
}
