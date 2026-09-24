# 13ft on Coolify

Deployable [13ft](https://github.com/wasi-master/13ft) ("13 Feet Ladder", MIT) — a
self-hosted 12ft.io alternative — with a custom landing page, behind one domain.

```
        Internet
           │
    ┌──────▼───────────────────────────────┐
    │ Coolify (Traefik + Let's Encrypt)    │
    └──────┬───────────────────────────────┘
           │  https://13ft.example.com
    ┌──────▼───────────────────────────────┐
    │ web  (nginx:alpine, :80)             │   ← only public service
    │   GET  /            → landing page   │      (this custom UI)
    │   everything else   → proxy ─────────┼──┐
    └──────────────────────────────────────┘  │
                                       ┌──────▼────────────────────────┐
                                       │ app (ghcr.io/.../13ft, :5000) │
                                       │   /<url>        bypass        │
                                       │   /status?url=  SSE progress  │
                                       │   /article      form POST     │
                                       │   /favicon.ico  upstream logo │
                                       └───────────────────────────────┘
```

## Files

| Path | Purpose |
| --- | --- |
| `docker-compose.yml` | Coolify stack: `app` (13ft) + `web` (nginx + landing page) |
| `docker-compose.simple.yml` | Upstream app alone (stock UI), for local testing |
| `web/site/index.html` | Custom landing page (self-contained: inline CSS/JS, no CDN) |
| `web/nginx.conf` | Reverse-proxy routing (only `/` is served locally) |
| `web/proxy_13ft.inc` | Shared proxy settings, incl. SSE-friendly timeouts/buffering |
| `.env.example` | All tunables with defaults |
| `scripts/smoke-test.sh` | Post-deploy check: page, proxy, form POST, SSE stream |

## Deploy on Coolify

1. **Push this folder to a Git repo** (GitHub/Gitea/etc.). Coolify needs the repo
   because `web` is built from source (`web/Dockerfile`), not pulled as an image.
2. Coolify → **Projects → + New Resource → Docker Compose** (private or public repo,
   whichever fits).
3. Settings:
   - **Base Directory:** `13ft-coolify`
   - **Docker Compose Location:** `/docker-compose.yml`
4. **Environment Variables** tab: add anything from `.env.example` you want to
   override. Defaults are already baked into the compose file, so you can deploy with
   none. Common ones:

   | Variable | Default | Notes |
   | --- | --- | --- |
   | `LOCALE` | `en` | App UI language: `en`, `de`, `fr`, `ko` |
   | `TZ` | `UTC` | Container timezone |
   | `GUNICORN_THREADS` | `8` | Concurrent fetches inside the single worker |
   | `GUNICORN_TIMEOUT` | `180` | Gunicorn request timeout in seconds |

5. **Domain:** set the FQDN on the **`web`** service, **port 80**. The compose file
   already declares Coolify's `SERVICE_FQDN_WEB_80` magic variable, so port 80 will be
   listed for that service — type your domain (`13ft.example.com`), pick `https`, and
   Coolify provisions the certificate. Do **not** add a domain to `app`; it has no
   published port by design.
6. **Deploy.** Coolify builds `web`, pulls the 13ft image, waits for the healthchecks,
   then routes the domain. First build is quick (just nginx + one HTML file).

### Alternative: no landing page

If you want the stock 13ft interface only, create a **Docker Compose** resource from
`docker-compose.simple.yml` and give `app` a domain on port 5000.

## Local test

```bash
cp .env.example .env
docker compose up -d --build          # then open http://localhost
# or just the upstream app, stock UI:
docker compose -f docker-compose.simple.yml up -d   # http://localhost:8080
```

Verify after deploying (works against localhost or your Coolify domain):

```bash
./scripts/smoke-test.sh https://13ft.example.com
```

## Why these gunicorn settings

The upstream image starts gunicorn with **stock defaults: one *sync* worker, 30s
timeout**. That is wrong for this app:

- A single fetch can take up to ~30s (the app's own HTTP timeout), plus archive
  fallbacks. A sync worker serves one request at a time, so any concurrent visitor
  waits, and gunicorn recycles the worker *mid-fetch* when the timeout hits.
- The compose file therefore sets `GUNICORN_CMD_ARGS` to a `gthread` worker with
  several threads and a longer timeout. `app/gunicorn.conf.py` still supplies
  `bind = 0.0.0.0:$PORT`, so only the concurrency settings change.

**`--workers` must stay at 1.** The app keeps the live-progress jobs and the rendered
page cache **in process memory** (`jobs`, `page_cache` in `app/portable.py`). With more
than one worker, the `EventSource` poll for `/status` can land on a worker that never
saw the job, and the progress page breaks. Need more throughput? Raise
`GUNICORN_THREADS`, not workers — and never scale this service to multiple replicas.

## Operations

- **Logs:** both containers log to stdout (gunicorn access/error logs are enabled), so
  Coolify's log view is complete.
- **Updating:** redeploy with a fresh pull of `ghcr.io/wasi-master/13ft:latest`. Pin a
  digest or tag in `docker-compose.yml` if you'd rather control upgrades.
- **Memory:** the page cache holds full rendered articles for ~5 minutes. A few hundred
  MB of RAM is plenty; raise the container limit if you serve big pages at volume.
- **Reachability:** only `web` is exposed; the app port is internal to the compose
  network.
- **Lock it down if it's public.** The endpoint has no authentication. An open instance
  invites abuse (and annoyed site operators). Options: Coolify's resource-level
  Basic Auth, Cloudflare Access, or Traefik middleware. Rate limiting is worth adding
  if you share the URL widely.

### Routing notes

- **Upstream never returns 404.** The app registers a catch-all `/<path:path>` route, so
  any unknown path is treated as a URL to bypass and answered with `400 Invalid URL`.
  That is also why the landing page is a **single self-contained file** — an external
  `/style.css` or `/app.js` request would be swallowed by that catch-all route instead
  of being served. If you ever split the assets, serve them from a path nginx handles
  itself (e.g. `location ^~ /assets/`) rather than from `/`.
- **`/favicon.ico`** is served by the app from `logo.png` in the upstream image; the
  landing page links to it, so the tab icon is the 13ft logo.
- **Only the exact path `/` is served locally.** Every other path is proxied
  untouched, which keeps `/status`, `/article` and the bypass routes working.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `502` from the proxy | `app` is unhealthy or still starting. Check its logs; healthcheck requires `GET /` on port 5000. |
| Progress page spins, then "Lost the connection" | `/status` stream is being buffered. The compose config disables buffering; if you added your own proxy in front, set `proxy_buffering off` for that path. |
| Every fetch fails with an anti-bot message | The target site blocks crawler user-agents and no archive snapshot exists yet (common for very recent Medium posts). Try another source. |
| Fetches die at ~30s | `GUNICORN_TIMEOUT` or the proxy read timeout is too low. Defaults here are 180s / 300s. |
| Domain shows the stock 13ft UI | The domain is attached to `app` (port 5000) instead of `web` (port 80). |
| Landing page loads but the bypass 404s | You're hitting a static-file server instead of the proxy — confirm `web` is built from `web/Dockerfile` and nginx.conf is the one in this repo. |

## Credit & scope

13ft is MIT-licensed work by [@wasi-master](https://github.com/wasi-master/13ft),
with contributions from its community. This repository only adds packaging
(compose + reverse proxy + landing page). Use it for the occasional paywalled
article, and subscribe to publications you read regularly.
