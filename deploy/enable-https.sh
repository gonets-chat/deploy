#!/bin/sh
# Issue the public certificate, then restart frontend with HTTPS enabled.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

docker compose up -d --build

# Wait for the local endpoint before contacting Let's Encrypt.
attempt=0
until docker compose exec -T frontend wget -q --spider http://127.0.0.1/healthz; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo "Frontend did not become ready; check docker compose logs frontend." >&2
        exit 1
    fi
    sleep 2
done

docker compose run --rm certbot certonly \
    --webroot --webroot-path /var/www/certbot \
    --cert-name openverse.site --domain openverse.site \
    --agree-tos --register-unsafely-without-email --non-interactive

docker compose restart frontend
attempt=0
until docker compose exec -T frontend wget -q --spider --no-check-certificate https://127.0.0.1/healthz; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        echo "HTTPS did not become ready; check docker compose logs frontend." >&2
        exit 1
    fi
    sleep 2
done
echo "HTTPS configured: https://openverse.site"
