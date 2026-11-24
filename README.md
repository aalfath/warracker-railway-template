[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/warracker-1?utm_medium=integration&utm_source=button&utm_campaign=warracker)

# Warracker on Railway

One-click [Railway](https://railway.com) template for [Warracker](https://github.com/sassanix/Warracker), the open-source warranty tracker: products, purchase dates, warranty expiry, receipts, manuals and photos, with expiry reminders.

**Version:** Warracker 1.0.7, official image `ghcr.io/sassanix/warracker/main:1.0.7@sha256:72fba72a19ac2f6710068010d3ff3dafcf47d52a4ddc7e8db3e35847fa8bb01c`.

## What it deploys

| Service | Source | What it does |
|---|---|---|
| **Warracker** | this repo (`Dockerfile`) | Web UI and API (nginx on `$PORT` in front of gunicorn), health check `/api/health`, volume at `/data` for uploaded receipts, documents, photos and the session key |
| **Postgres** | Railway's Postgres | Stores users, warranties, tags and settings, on its own volume |

The wrapper (`railway-start.sh`, `railway_init.py`, `railway-run.sh`) only adapts the upstream image to Railway:

- nginx listens on Railway's `PORT`, uses one worker per CPU the service really has, and reads the visitor's IP from Railway's proxy, so the app's login rate limit works per visitor.
- On first boot it runs the database migrations under a Postgres lock and creates the **admin account** from `ADMIN_USERNAME` / `ADMIN_PASSWORD`, then **closes public sign-up**. Upstream would otherwise make the first visitor who registers the owner of the instance.
- If supervisord, nginx or gunicorn die, the container exits non-zero so Railway's restart policy brings it back.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_USERNAME` | `admin` | First admin account, created on first boot only |
| `ADMIN_EMAIL` | `admin@example.com` | Change it in the app's settings later |
| `ADMIN_PASSWORD` | generated | Find it in the Warracker service's Variables tab. Changing the variable later does not change the password: change it in the app |
| `SECRET_KEY` | generated | Signs sessions and tokens |
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | Private-network connection to Postgres |
| `PORT` | `8080` | Port nginx listens on |

Optional, add them yourself when you need them (see upstream `env.example`): `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM_ADDRESS` for password-reset and expiry emails; `APPRISE_*` for push notifications; `OIDC_*` for single sign-on; `MAX_UPLOAD_MB` and `NGINX_MAX_BODY_SIZE_VALUE` for bigger uploads.

## Resources

Runs on Railway's Free plan limits (0.5 GB RAM, 1 vCPU per service): about 120 MB idle and under 190 MB peak while uploading files, tested on Railway.

## Updates

This template builds from this repository. When a new Warracker release is tested, we bump the pinned image here and add a `CHANGELOG.md` entry; Railway then shows an "update available" notice on your project, and you choose when to apply it. Database migrations run automatically on the next start. Read the changelog before you apply an update.

## Licence

Warracker is AGPL-3.0, by [sassanix](https://github.com/sassanix/Warracker). This wrapper is MIT.
