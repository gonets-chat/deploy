# Развёртывание OpenVerse

Вариант для Linux VPS с Docker Compose и внешним HTTPS-прокси.
Нужен только репозиторий deploy: `compose.yaml`, `.dockerignore` и `deploy/`.
Docker BuildKit скачивает исходники напрямую из публичных репозиториев:

- https://github.com/gonets-chat/backend.git
- https://github.com/gonets-chat/frontend.git

Локальные каталоги `backend/` и `frontend/` для сборки не используются.
Нужны Docker BuildKit/Buildx и Docker Compose версии 2.17 или новее.

## Первый запуск

Из корня проекта на сервере:

```sh
cp .env.example .env
chmod 600 .env
```

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
docker compose up -d --build
docker compose ps -a
docker compose logs --tail=100 backend worker migrate
curl --fail http://127.0.0.1:8080/healthz
curl --fail http://127.0.0.1:8080/openapi.json
```

Контейнер `migrate` должен завершиться с кодом `0`. API и worker запускаются
после готовности зависимостей и успешных миграций — через условия
[`depends_on`](https://docs.docker.com/compose/how-tos/startup-order/).
Healthcheck API проверяет HTTP, а не доступность БД после запуска.

## Подключение HTTPS

Внешний прокси на этом же сервере направь на `http://127.0.0.1:8080`.
Передавай исходный `Host`, `X-Forwarded-Proto: https` и поддерживай WebSocket
Upgrade для `/ws`. Проксируй все пути без удаления префиксов.

Если прокси работает в контейнере, его `127.0.0.1` не является хостом VPS:
подключи прокси к сети этого Compose и используй `frontend:80`.
При прокси на другом сервере укажи в `BIND_ADDRESS` приватный IP VPS и разреши
доступ к порту только с адреса прокси.

Браузер открывает один HTTPS-домен: Nginx отдаёт React и передаёт `/auth`,
`/chat`, `/users`, `/ws`, `/docs`, `/redoc`, `/openapi.json` в API.
Клиентские маршруты React, включая `/messenger`, работают при обновлении страницы.
В production (`DEBUG=false`) cookies имеют флаг Secure, поэтому вход проверяй
через публичный HTTPS-адрес. HTTPS и сертификаты настраиваются внешним прокси.

## Состав

- `frontend`: сборка React/Vite и Nginx; единственный опубликованный порт.
- `backend`: FastAPI, один Uvicorn worker, без reload.
- `worker`: Taskiq для фоновых задач.
- `migrate`: одноразовый запуск `alembic upgrade head`.
- `db`, `redis`: внутренние сервисы с постоянными Docker volumes, без портов хоста.

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
`docker compose down -v` удаляет данные PostgreSQL и Redis.
Изменение пароля в `.env` не меняет пароль уже созданной базы.
