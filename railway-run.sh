#!/bin/bash
# Runs upstream supervisord and exits non-zero when it stops or when nginx or
# gunicorn stay down, because supervisord keeps running (and exits 0) after a
# child gives up. A non-zero exit lets Railway's ON_FAILURE policy restart us.
set -u
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] railway: $*"; }

/opt/venv/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf &
SUP=$!
trap 'kill -TERM "$SUP" 2>/dev/null; wait "$SUP"; exit 0' TERM INT

sleep 45
misses=0
while true; do
  if ! kill -0 "$SUP" 2>/dev/null; then
    wait "$SUP"; code=$?
    log "supervisord stopped (exit ${code}); exiting 1 so Railway restarts the service"
    exit 1
  fi
  if pgrep -f 'gunicorn --config' >/dev/null && pgrep -x nginx >/dev/null \
     && curl -fsS -m 10 -o /dev/null "http://127.0.0.1:${PORT}/api/health"; then
    misses=0
  else
    misses=$((misses + 1))
    log "health check failed (${misses}/6)"
    if [ "$misses" -ge 6 ]; then
      log "app unhealthy for about 2 minutes; exiting 1 so Railway restarts the service"
      kill -TERM "$SUP" 2>/dev/null; sleep 5
      exit 1
    fi
  fi
  sleep 20
done
