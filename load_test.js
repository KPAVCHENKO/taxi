import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,          // 10 одновременных пользователей
  duration: '30s',  // в течение 30 секунд
};

const BASE = 'https://kazanskoe-taxi.xyz';

export default function () {
  // Главная страница
  let r = http.get(BASE + '/');
  check(r, { 'главная 200': (r) => r.status === 200 });

  sleep(1);

  // Тарифы (API)
  r = http.get(BASE + '/api/tariffs');
  check(r, { 'тарифы 200': (r) => r.status === 200 });

  sleep(1);
}
