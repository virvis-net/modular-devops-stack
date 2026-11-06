#!/bin/sh
set -eu

nohup npm run dev > /tmp/vite-dev-server.log 2>&1 </dev/null &
