FROM dunglas/frankenphp:1-php8.5-bookworm AS app

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && install-php-extensions mbstring opcache pcntl pdo_mysql pdo_sqlite zip opentelemetry

WORKDIR /var/www/html

FROM app AS build

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY . .
RUN mkdir -p storage/framework/cache/data storage/framework/sessions \
        storage/framework/views storage/logs bootstrap/cache \
    && test -f composer.lock \
    && composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --no-progress \
    --no-scripts \
    --optimize-autoloader
RUN php artisan package:discover --ansi

FROM app AS devcontainer

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
RUN apt-get update \
    && apt-get install -y --no-install-recommends git openssh-client \
    && rm -rf /var/lib/apt/lists/*
ENV APP_ENV=local \
    APP_DEBUG=true

FROM app AS runtime

ENV APP_ENV=production \
    APP_DEBUG=false \
    LOG_CHANNEL=stderr \
    OTEL_PHP_AUTOLOAD_ENABLED=true \
    XDG_CONFIG_HOME=/tmp/caddy/config \
    XDG_DATA_HOME=/tmp/caddy/data

WORKDIR /var/www/html
COPY --from=build --chown=www-data:www-data /var/www/html ./
RUN mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" \
    && chown -R www-data:www-data "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
USER www-data
EXPOSE 8080
EXPOSE 9090
ENTRYPOINT ["bash", "docker/entrypoint.sh"]
