#!/bin/sh
set -eu

case "$1" in
  *Username*)
    printf '%s\n' "${GITEA_USERNAME:-}"
    ;;
  *Password*)
    printf '%s\n' "${GITEA_ACCESS_TOKEN:-}"
    ;;
  *)
    exit 1
    ;;
esac
