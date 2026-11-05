# syntax=docker/dockerfile:1
FROM node:24-alpine AS builder
WORKDIR /app
COPY --from=frontend_source /package.json /package-lock.json ./
RUN npm ci
COPY --from=frontend_source / ./
RUN npm run build

FROM nginx:stable-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
