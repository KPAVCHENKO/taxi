import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Краткое руководство для водителя: как принимать и выполнять заказы.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Как пользоваться')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _step('1', '🟢 Встаньте на смену',
              'Включите переключатель «На смене» вверху. Без смены заказы не приходят. '
              'Закончили работать — снимитесь со смены.'),
          _step('2', '🔔 Новый заказ',
              'Заказ приходит на весь экран со звуком — даже при заблокированном телефоне. '
              'Нажмите «Принять», пока идёт таймер, или пропустите — заказ уйдёт другому.'),
          _step('3', '🧭 Едете к пассажиру',
              '«Маршрут» → «К пассажиру» откроет Навигатор или 2ГИС. '
              '«Позвонить» — связаться, «Чат с пассажиром» — написать.'),
          _step('4', '🚗 Я на месте',
              'Подъехали — нажмите «Я на месте». Пассажир получит уведомление, что вы приехали.'),
          _step('5', '✅ Завершите поездку',
              'В конце нажмите «Завершить» и введите фактическую сумму — она прибавится к заработку.'),
          _step('6', '⭐ Рейтинг',
              'Пассажиры ставят оценку после поездки. Будьте вежливы и аккуратны — рейтинг виден.'),
          _step('7', '💰 Заработок',
              'В разделе «Ещё» — заработок за день/неделю/месяц, баланс и число поездок.'),
          _step('8', '🔊 Звук и надёжность',
              '«Звук и вибрация» — сигнал входящего заказа. «Надёжная работа» — обязательно '
              'отключите экономию батареи, чтобы заказы приходили при закрытом приложении.'),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: const Text('Вопросы — звоните диспетчеру. Удачной работы! 🚖',
                style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String title, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: Text(n, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
