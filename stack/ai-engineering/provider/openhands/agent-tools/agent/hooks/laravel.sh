# Sourced by prepare.sh. Uses ok, warn, fail and run from there.
stack_prepare() {
  # PHP dependencies must be present before any artisan command works
  if [ ! -f vendor/autoload.php ]; then
    run composer install --no-interaction >/dev/null \
      || fail "composer install failed" 8
    warn "vendor was missing, ran composer install"
  fi
  ok "php dependencies present"

  # Only ever reset a development or testing database
  local app_env
  app_env="$(run printenv APP_ENV || true)"
  case "$app_env" in
    local|testing) ;;
    *) fail "refusing to reset the database: APP_ENV is '$app_env', expected local or testing" 8 ;;
  esac

  run php artisan migrate:fresh --force >/dev/null \
    || fail "migrate:fresh failed on main, so the migrations on main do not run cleanly" 8
  ok "database reset and migrated to the state of main"
}
