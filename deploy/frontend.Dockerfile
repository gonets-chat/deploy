# syntax=docker/dockerfile:1
FROM node:24-alpine AS builder
WORKDIR /app
COPY --from=frontend_source /package.json /package-lock.json ./
RUN npm ci
COPY --from=frontend_source / ./
RUN npm run build

FROM nginx:stable-alpine
COPY deploy/nginx.conf /etc/nginx/openverse-https.conf
COPY deploy/nginx.http.conf /etc/nginx/openverse-http.conf
COPY deploy/nginx.app.conf /etc/nginx/openverse-app.conf
COPY --chmod=755 deploy/40-select-https.sh /docker-entrypoint.d/40-select-https.sh
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80 443
