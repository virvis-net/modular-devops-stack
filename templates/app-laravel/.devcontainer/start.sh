#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .env ]; then
    cp .env.example .env
fi

composer install

if ! grep -q '^APP_KEY=base64:' .env; then
    php artisan key:generate --force
fi

exec bash docker/entrypoint.sh
