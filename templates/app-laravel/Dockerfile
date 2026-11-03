FROM php:8.3-cli-bookworm AS app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libonig-dev libsqlite3-dev libzip-dev \
    && docker-php-ext-install mbstring pdo_mysql pdo_sqlite zip \
    && pecl install opentelemetry \
    && docker-php-ext-enable opentelemetry \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

FROM app AS build

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY . .
RUN mkdir -p storage/framework/cache/data storage/framework/sessions \
        storage/framework/views storage/logs bootstrap/cache \
    && composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --no-progress \
    --no-scripts \
    --optimize-autoloader
RUN php artisan package:discover --ansi

FROM app AS runtime

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    OTEL_PHP_AUTOLOAD_ENABLED=true

WORKDIR /var/www/html
COPY --from=build --chown=www-data:www-data /var/www/html ./
USER www-data
EXPOSE 8080
EXPOSE 9090
CMD ["bash", "docker/entrypoint.sh"]
