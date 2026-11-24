#!/usr/bin/env python
"""First-boot step for Warracker on Railway.

1. Takes a Postgres advisory lock (polled, so overlapping Railway deploys run
   migrations one at a time).
2. Runs the upstream migrations.
3. If the database has no users yet, creates the first admin (owner) from
   ADMIN_USERNAME / ADMIN_EMAIL / ADMIN_PASSWORD and closes public registration,
   so nobody else can sign up and claim the instance. Later boots change nothing:
   password and settings changes made in the app are kept.
"""
import os
import subprocess
import sys
import time

import bcrypt
import psycopg2

LOCK_KEY = 73060001  # advisory lock id used only by this script


def log(msg):
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] railway: {msg}", flush=True)


def connect():
    url = os.environ.get("DATABASE_URL")
    kwargs = {"dsn": url} if url else {
        "host": os.environ.get("DB_HOST", "warrackerdb"),
        "port": os.environ.get("DB_PORT", "5432"),
        "dbname": os.environ.get("DB_NAME", "warranty_db"),
        "user": os.environ.get("DB_USER"),
        "password": os.environ.get("DB_PASSWORD"),
    }
    last = None
    # Railway's private DNS can take a minute to resolve on a first deploy.
    for attempt in range(1, 61):
        try:
            conn = psycopg2.connect(connect_timeout=5, **kwargs)
            conn.autocommit = True
            return conn
        except psycopg2.OperationalError as e:
            last = e
            if attempt % 5 == 1:
                log(f"waiting for Postgres (attempt {attempt}/60): {str(e).strip().splitlines()[0]}")
            time.sleep(3)
    log(f"ERROR: could not connect to Postgres: {last}")
    sys.exit(1)


def main():
    conn = connect()
    cur = conn.cursor()

    waited = 0
    while True:
        cur.execute("SELECT pg_try_advisory_lock(%s)", (LOCK_KEY,))
        if cur.fetchone()[0]:
            break
        if waited % 30 == 0:
            log("another instance is running first-boot setup; waiting")
        time.sleep(2)
        waited += 2
        if waited > 600:
            log("ERROR: setup lock not released after 10 minutes")
            sys.exit(1)

    try:
        log("applying database migrations")
        res = subprocess.run(
            [sys.executable, "/app/migrations/apply_migrations.py"],
            cwd="/app", stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        if res.returncode != 0:
            print(res.stdout[-6000:], flush=True)
            log("ERROR: migrations failed")
            sys.exit(1)
        applied = res.stdout.count("Applying migration:")
        log(f"migrations done ({applied} applied now)")

        cur.execute("SELECT COUNT(*) FROM users")
        if cur.fetchone()[0] > 0:
            log("users already exist; first-admin step skipped")
            return

        username = (os.environ.get("ADMIN_USERNAME") or "admin").strip()
        email = (os.environ.get("ADMIN_EMAIL") or "admin@example.com").strip()
        password = os.environ.get("ADMIN_PASSWORD") or ""
        if len(password) < 8:
            log("ERROR: ADMIN_PASSWORD must be set (8+ characters) for the first admin account")
            sys.exit(1)
        if len(password.encode()) > 72:
            log("ERROR: ADMIN_PASSWORD must not exceed 72 bytes")
            sys.exit(1)

        pw_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt(12)).decode()
        cur.execute("BEGIN")
        cur.execute(
            "INSERT INTO users (username, email, password_hash, first_name, last_name,"
            " is_active, is_admin, is_owner) VALUES (%s, %s, %s, %s, %s, TRUE, TRUE, TRUE)",
            (username, email, pw_hash, "Admin", ""),
        )
        cur.execute(
            "INSERT INTO site_settings (key, value) VALUES ('registration_enabled', 'false')"
            " ON CONFLICT (key) DO UPDATE SET value = 'false', updated_at = CURRENT_TIMESTAMP"
        )
        cur.execute("COMMIT")
        log(f"created first admin '{username}' and closed public registration")
    finally:
        try:
            cur.execute("SELECT pg_advisory_unlock(%s)", (LOCK_KEY,))
        except Exception:
            pass
        conn.close()


if __name__ == "__main__":
    main()
