# Sourced by prepare.sh. Uses ok, warn, fail and run from there.
stack_prepare() {
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
