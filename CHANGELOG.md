# Changelog

## 1.0.7 (2026-11-24)

First release of this template.

- Warracker 1.0.7, official image pinned by digest (`sha256:72fba72a…`).
- Railway Postgres, volume `/data` for uploads and the session key.
- First admin account created on first boot from generated variables; public sign-up closed.
- nginx on `$PORT`, worker count from the service's CPU limit, visitor IP taken from Railway's proxy.
- The container exits non-zero when the app stops, so Railway restarts it.
