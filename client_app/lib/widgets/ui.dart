import 'package:flutter/material.dart';

import '../config/config.dart';
import '../config/theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}

class CtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const CtaButton({super.key, required this.label, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [p.accent2, p.accent],
          ),
          boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: ElevatedButton(
          onPressed: busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: C.accentInk,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: busy
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.accentInk))
              : Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.accentInk)),
        ),
      ),
    );
  }
}

/// Сегмент-переключатель (как чипсы на сайте).
class Segmented extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Row(
      children: [
        for (final o in options) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: value == o ? p.accent.withValues(alpha: 0.16) : p.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: value == o ? p.accent : Colors.transparent, width: 1.5),
                ),
                child: Text(o,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: value == o ? p.accent : p.text2)),
              ),
            ),
          ),
          if (o != options.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

/// Поле «выбрать населённый пункт» (открывает список).
class SettlePicker extends StatelessWidget {
  final String label;
  final String? display;
  final VoidCallback onTap;
  final Color dotColor;
  const SettlePicker({
    super.key,
    required this.label,
    required this.display,
    required this.onTap,
    required this.dotColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: p.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, color: p.text3, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(display ?? 'Выберите населённый пункт',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: display == null ? p.text3 : p.text)),
                ],
              ),
            ),
            Icon(Icons.expand_more, color: p.text3),
          ],
        ),
      ),
    );
  }
}

/// Показать список населённых пунктов и вернуть выбранный.
Future<Settle?> pickSettlement(BuildContext context, String title) {
  final p = palette(context);
  return showModalBottomSheet<Settle>(
    context: context,
    backgroundColor: p.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (c, controller) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: heading(size: 18, color: p.text)),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: Settlements.all.length,
                itemBuilder: (c, i) {
                  final s = Settlements.all[i];
                  return ListTile(
                    title: Text(s.label, style: TextStyle(fontSize: 17, color: p.text, fontWeight: FontWeight.w600)),
                    trailing: s.intercity ? Text('межгород', style: TextStyle(color: p.text3, fontSize: 12)) : null,
                    onTap: () => Navigator.pop(ctx, s),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
