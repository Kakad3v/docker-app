FROM composer:2.4.3 as vendor

COPY database/ database/
COPY composer.json composer.json
COPY composer.lock composer.lock

RUN composer install \
    --ignore-platform-reqs \
    --no-interaction \
    --no-plugins \
    --no-scripts \
    --optimize-autoloader \
    --prefer-dist


FROM node:18-alpine as frontend

RUN mkdir -p /app/public

COPY package.json /app/
COPY resources/js/ /app/resources/js/
COPY resources/css/ /app/resources/css/

WORKDIR /app
RUN npm install && npm build


FROM php:8.2-fpm
LABEL maintainer="Kakadev"

RUN apt-get update && apt-get install -y git zip unzip

RUN curl --silent --show-error --fail --location \
      --header "Accept: application/tar+gzip, application/x-gzip, application/octet-stream" -o - \
    "https://caddyserver.com/download/linux/amd64?plugins=http.expires,http.realip&license=personal&telemetry=off" \
    | tar --no-same-owner -C /usr/bin/ -xz caddy \
    && chmod 0755 /usr/bin/caddy \
    && /usr/bin/caddy -version \
    && docker-php-ext-install mbstring pdo pdo_mysql opcache

WORKDIR /var/www/

COPY . /var/www/

COPY --from=vendor /app/vendor/ /var/www/vendor/
COPY --from=frontend /app/public/js/ /var/www/public/js/
COPY --from=frontend /app/public/css/ /var/www/public/css/

COPY .docker/Caddyfile /etc/Caddyfile
COPY .docker/config/* $PHP_INI_DIR/conf.d/

RUN chown -R www-data:www-data /var/www/

# laravel setup
RUN mv .env.prod .env
RUN php artisan migrate \
    && php artisan config:cache \
    && php artisan route:cache

EXPOSE 2015

CMD ["/usr/bin/caddy", "-agree=true", "-conf=/etc/Caddyfile"]