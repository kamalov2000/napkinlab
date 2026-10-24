# 00 — запуск стенда

## Что нужно
- Docker Desktop (Windows: с бэкендом WSL2) или Docker на Linux/macOS.
- `make` и `bash` (в WSL, Linux, macOS или Git Bash они есть).
- ~4 ГБ свободной памяти, ~1 ГБ диска.

## Шаги
```bash
make up                      # postgres, redis, api — ждём healthy
make seed N=1000000          # миллион ссылок, 1–2 минуты
curl -X POST localhost:8080/shorten -d '{"url":"https://habr.com"}'
curl -I localhost:8080/<code из ответа>
```

## Что должно получиться
`make up` заканчивается таблицей из трёх контейнеров, у всех в STATUS `(healthy)`:

```
NAME                   SERVICE    STATUS
napkinlab-api-1        api        Up ... (healthy)
napkinlab-postgres-1   postgres   Up ... (healthy)
napkinlab-redis-1      redis      Up ... (healthy)
```

`make seed` печатает прогресс каждые 100 000 строк, в конце — число строк, размер таблицы
и пишет 20 случайных кодов в `results/sample_codes.txt`.

`curl -I` возвращает `HTTP/1.1 302 Found` и заголовок `Location` с исходной ссылкой.

Счётчики сервиса: `curl localhost:8080/metrics`.

## Если что-то не так
- `make logs` — логи всех контейнеров.
- Порт 8080 занят — поменяйте `API_PORT` в `.env`.
- Начать с нуля — `make clean`, затем снова `make up`.

Дальше — [01-estimate.md](01-estimate.md).
