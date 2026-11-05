#!/bin/sh
# Renew certificates and make Nginx load the current certificate files.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

docker compose run --rm certbot renew --quiet
docker compose exec -T frontend nginx -t
docker compose exec -T frontend nginx -s reload
