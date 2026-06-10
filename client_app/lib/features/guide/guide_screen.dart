import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../widgets/ui.dart';

/// Краткое руководство для пассажира: как заказать и пользоваться.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = palette(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Как заказать')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _step(p, '1', '📍 Выберите маршрут',
              'Укажите «Откуда» и «Куда» из списка сёл или поставьте точку на карте (кнопка 🗺).'),
          _step(p, '2', '💰 Узнайте цену',
              'Цена показывается сразу — это ориентир. Итоговую сумму подтвердит водитель.'),
          _step(p, '3', '📞 Оставьте телефон',
              'Введите номер и нажмите «Заказать». Заказываете другому — отметьте галочку и впишите телефон пассажира.'),
          _step(p, '4', '🔎 Следите за статусом',
              'На экране заказа: «ищем водителя» → «принял» (имя и авто) → «водитель на месте» → «поездка завершена».'),
          _step(p, '5', '💬 Связь с водителем',
              'Когда заказ принят — кнопки «Позвонить водителю» и «Написать водителю».'),
          _step(p, '6', '🏠 Избранные адреса',
              'Сохраните Дом и Работу — в следующий раз выберете их в один тап.'),
          _step(p, '7', '⭐ Оцените поездку',
              'После завершения поставьте оценку — это помогает держать качество сервиса.'),
          _step(p, '8', '✖ Отмена',
              'Пока водитель не приехал, заказ можно отменить на экране заказа.'),
          const SizedBox(height: 4),
          AppCard(
            child: Text('Нет интернета? Закажите в Telegram-боте или позвоните диспетчеру.',
                style: TextStyle(color: p.text2, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _step(AppPalette p, String n, String title, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.text)),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(fontSize: 14, height: 1.45, color: p.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
