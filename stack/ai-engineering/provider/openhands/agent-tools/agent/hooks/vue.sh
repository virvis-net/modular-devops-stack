stack_prepare() {
  [ -d node_modules ] || run npm ci >/dev/null || fail "npm ci failed" 8
  ok "node dependencies present"
}
