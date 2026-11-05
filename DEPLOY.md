# Развёртывание OpenVerse

Linux VPS с Docker Compose. Nginx внутри frontend напрямую принимает
HTTP/HTTPS на портах 80/443 для `openverse.site`.
Нужен только репозиторий deploy: `compose.yaml`, `.dockerignore` и `deploy/`.
Docker BuildKit скачивает исходники напрямую из публичных репозиториев:

- https://github.com/gonets-chat/backend.git
- https://github.com/gonets-chat/frontend.git

Локальные каталоги `backend/` и `frontend/` для сборки не используются.
Нужны Docker BuildKit/Buildx и Docker Compose версии 2.17 или новее.

## Первый запуск

Из корня проекта на сервере:

У домена должна быть A-запись `31.77.204.59`. AAAA-запись оставляй только если
IPv6 тоже ведёт на этот VPS и сайт доступен по нему. TCP-порты 80/443 должны
быть свободны и доступны из интернета, включая firewall Timeweb.

```sh
cp .env.example .env
chmod 600 .env
```

Если `.env` уже заполнен, сохрани его. Установи
`WS_ALLOWED_ORIGINS='["https://openverse.site"]'`.
Старые `BIND_ADDRESS` и `HTTP_PORT` больше не используются.

GitHub-токен, файл `.github-token` и SSH-ключи для скачивания исходников не нужны.

Заполни `.env`: укажи публичный домен в `WS_ALLOWED_ORIGINS`, случайный пароль
PostgreSQL и отдельный `SECRET_KEY` длиной минимум 32 символа. Значения можно
сгенерировать двумя вызовами `openssl rand -hex 32`. В пароле PostgreSQL не
используй `%`: текущая конфигурация Alembic не экранирует его для ConfigParser.
По умолчанию скачивается текущая версия основной ветки каждого репозитория.
Для конкретной версии задай `BACKEND_GIT_REF` и `FRONTEND_GIT_REF` в `.env`:
ветку, тег или полный SHA коммита. SHA позволяет повторить ту же сборку.

```sh
docker compose config --quiet
sh deploy/enable-https.sh
docker compose ps -a
docker compose logs --tail=100 backend worker migrate
curl --fail https://openverse.site/healthz
curl --fail https://openverse.site/openapi.json
```

Контейнер `migrate` должен завершиться с кодом `0`. API и worker запускаются
после готовности зависимостей и успешных миграций — через условия
[`depends_on`](https://docs.docker.com/compose/how-tos/startup-order/).
Healthcheck API проверяет HTTP, а не доступность БД после запуска.

## Подключение HTTPS

Скрипт `enable-https.sh` собирает образы и запускает HTTP-конфигурацию Nginx,
если сертификата ещё нет. Затем выпускает сертификат Let’s Encrypt через
[Certbot webroot](https://eff-certbot.readthedocs.io/en/stable/using.html#webroot)
и перезапускает frontend с HTTPS. Команда принимает условия Let’s Encrypt
(`--agree-tos`), аккаунт регистрируется без email. Повторный запуск использует
действующий сертификат, если он ещё не требует обновления.

После выпуска HTTP перенаправляется на HTTPS, кроме `/healthz` и пути
проверки сертификата. TCP-порт 80 оставь доступным для продления через HTTP-01.
При ошибке выпуска проверь DNS, AAAA, доступность порта 80 и вывод Certbot.

Браузер открывает один HTTPS-домен: Nginx отдаёт React и передаёт `/auth`,
`/chat`, `/users`, `/ws`, `/docs`, `/redoc`, `/openapi.json` в API.
Клиентские маршруты React, включая `/messenger`, работают при обновлении страницы.
В production (`DEBUG=false`) cookies имеют флаг Secure, поэтому вход проверяй
через публичный HTTPS-адрес. Nginx сам завершает TLS.

Если меняешь домен, обнови `deploy/nginx.conf`, `deploy/nginx.http.conf`,
`deploy/40-select-https.sh`, `deploy/enable-https.sh` и `WS_ALLOWED_ORIGINS`.

## Продление сертификата

Проверь продление через тестовый сервер Let’s Encrypt:

```sh
docker compose run --rm certbot renew --dry-run
```

В root crontab (`crontab -e`) добавь одну строку. Путь соответствует
репозиторию в `/root/deploy`; для другого расположения измени его:

```cron
17 3,15 * * * /usr/bin/flock -n /var/lock/openverse-certbot.lock /bin/sh /root/deploy/deploy/renew-https.sh >> /var/log/openverse-certbot.log 2>&1
```

Дважды в сутки Certbot проверяет необходимость продления. После успешной
проверки скрипт выполняет `nginx -t` и reload. Ошибки попадут в лог
`/var/log/openverse-certbot.log`. Сертификаты и ACME webroot хранятся в volumes
`letsencrypt` и `acme_webroot`; frontend получает их только для чтения.

## Состав

- `frontend`: React/Vite и Nginx; опубликованы порты 80/443.
- `backend`: FastAPI, один Uvicorn worker, без reload.
- `worker`: Taskiq для фоновых задач.
- `migrate`: одноразовый запуск `alembic upgrade head`.
- `db`, `redis`: внутренние сервисы с постоянными Docker volumes, без портов хоста.
- `certbot`: запускается скриптами по запросу, профиль `tools`.

API оставлен в одном экземпляре: текущий менеджер WebSocket хранит соединения
в памяти процесса. Масштабирование требует отдельной доработки доставки событий.
Существующий `backend/docker-compose.yml` служит для локальной разработки;
на сервере запускай Compose из корня.

## Обновление

Обнови репозиторий deploy командой `git pull --ff-only`. Если используешь
фиксированные SHA, обнови их в `.env`. Затем из корня:

```sh
docker compose build
docker compose stop frontend backend worker
docker compose up -d --force-recreate migrate backend worker frontend
docker compose ps -a
docker compose logs --tail=100 migrate backend worker
```

Команда повторно применяет миграции перед запуском новой версии. На время
обновления сайт недоступен. Перед миграциями сделай резервную копию PostgreSQL.
При ошибке миграций проверь логи `migrate`; API и worker не запустятся.

Остановка с сохранением данных: `docker compose down`.
`docker compose down -v` удаляет данные PostgreSQL, Redis и сертификаты.
Изменение пароля в `.env` не меняет пароль уже созданной базы.
