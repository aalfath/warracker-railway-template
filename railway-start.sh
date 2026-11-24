#!/bin/bash
# Railway wrapper for Warracker: adapts the upstream image to Railway, then
# hands over to the upstream entrypoint (migrations, nginx config, supervisor).
set -euo pipefail
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] railway: $*"; }

export PORT="${PORT:-8080}"
export UPLOAD_FOLDER="${UPLOAD_FOLDER:-/data/uploads}"

# Public URL for login redirects, email links and the Secure session cookie.
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export FRONTEND_URL="${FRONTEND_URL:-https://${RAILWAY_PUBLIC_DOMAIN}}"
  export APP_BASE_URL="${APP_BASE_URL:-https://${RAILWAY_PUBLIC_DOMAIN}}"
fi

if [ -z "${DATABASE_URL:-}" ] && [ -z "${DB_PASSWORD:-}" ]; then
  log "ERROR: DATABASE_URL is not set. Point it at Postgres, e.g. \${{Postgres.DATABASE_URL}}."
  exit 1
fi

# nginx listens on $PORT instead of 80.
sed -i -E "s/listen (\[::\]:)?[0-9]+;/listen \1${PORT};/" /etc/nginx/conf.d/default.conf.template

# Railway's edge connects from 100.64.0.0/10; take the visitor's address from
# X-Forwarded-For so the app's per-IP login rate limit applies per visitor
# instead of locking everyone out together.
if ! grep -q "set_real_ip_from" /etc/nginx/conf.d/default.conf.template; then
  sed -i "0,/server_name localhost;/s//server_name localhost;\n    set_real_ip_from 100.64.0.0\/10;\n    real_ip_header X-Forwarded-For;/" /etc/nginx/conf.d/default.conf.template
fi

# One nginx worker per CPU the service really has (Railway shows the host's CPUs).
cpus=1
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r quota period < /sys/fs/cgroup/cpu.max || true
  if [ "${quota:-max}" != "max" ] && [ -n "${period:-}" ] && [ "$period" -gt 0 ]; then
    cpus=$(( (quota + period - 1) / period ))
  else
    cpus=$(nproc 2>/dev/null || echo 1)
  fi
fi
[ "$cpus" -lt 1 ] && cpus=1
[ "$cpus" -gt 4 ] && cpus=4
sed -i -E "s/^worker_processes .*/worker_processes ${cpus};/" /etc/nginx/nginx.conf
log "nginx: port ${PORT}, ${cpus} worker(s)"

mkdir -p "$UPLOAD_FOLDER"

# Upstream polls port 80 for its "healthy" banner; point it at $PORT.
sed -i "s|http://localhost/api/health|http://localhost:${PORT}/api/health|" /app/entrypoint.sh

# Locked first-boot step: migrations (one container at a time), first admin
# account from ADMIN_USERNAME/ADMIN_PASSWORD, public registration closed.
/opt/venv/bin/python /app/railway_init.py

# Upstream entrypoint (re-checks migrations, prepares nginx) then our runner.
exec /app/entrypoint.sh /app/railway-run.sh
