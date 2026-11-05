#!/bin/sh
# Select HTTP bootstrap or HTTPS configuration before Nginx starts.
set -eu

if [ -s /etc/letsencrypt/live/openverse.site/fullchain.pem ] &&
   [ -s /etc/letsencrypt/live/openverse.site/privkey.pem ]; then
    cp /etc/nginx/openverse-https.conf /etc/nginx/conf.d/default.conf
else
    cp /etc/nginx/openverse-http.conf /etc/nginx/conf.d/default.conf
fi
