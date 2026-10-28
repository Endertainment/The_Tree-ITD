# Prompt: build the backend for *The Tree — ITD*

Use this prompt with a coding agent (or as a spec) to create a small FastAPI +
PostgreSQL (Neon) service for the Godot game **The Tree — ITD**. It serves two
things: **remote bundle offers** (so offers can be added, reordered or disabled
without shipping an app update) and a **best-wave leaderboard**.

---

## Role

You are a senior backend engineer. Build a production-quality but small service:
FastAPI, SQLAlchemy 2.0 (async), asyncpg, Alembic, Pydantic v2, PostgreSQL on
Neon, deployed with uvicorn behind a reverse proxy. No frontend, no admin UI.

## Stack and project layout

```
app/
  main.py            FastAPI app, CORS, lifespan, /health
  config.py          pydantic-settings (DATABASE_URL, TOKEN_SECRET, ENV)
  db.py              async engine + session dependency
  models.py          SQLAlchemy models
  schemas.py         Pydantic request/response models
  security.py        anonymous tokens, HMAC verification, rate limiting
  routers/
    bundles.py
    devices.py
    runs.py
    leaderboard.py
alembic/
tests/               pytest + httpx AsyncClient against a test database
pyproject.toml
Dockerfile
README.md
```

Environment variables: `DATABASE_URL` (Neon, `postgresql+asyncpg://…?sslmode=require`),
`TOKEN_SECRET` (32+ random bytes), `ENV` (`dev`/`prod`), `CORS_ORIGINS`.

## 1. Bundle config (no app update required)

The Godot client fetches this JSON on launch, caches it in `user://bundles_cache.json`
and falls back to a bundled default in `res://data/bundles.json`.

```
GET /v1/bundles
200 {"version": 3, "bundles": [
  {"id":"starter","product_id":"starter_bundle","title":"STARTER PACK",
   "subtitle":"300 Gems · 3000 Gold","icon":"gems","order":10,"enabled":true},
  {"id":"gems_550","product_id":"gems_550","title":"GEM POUCH",
   "subtitle":"550 Gems","icon":"gems","order":20,"enabled":true}
]}
```

- Served from a `bundles` table (id, product_id, title, subtitle, icon, order,
  enabled, starts_at, ends_at, platforms, updated_at) so operators can add,
  disable or schedule offers with SQL, without a deploy.
- Filter by `enabled`, `starts_at <= now() < ends_at`, `platforms` containing
  `android`/`ios`, ordered by `order`.
- `ETag`/`Cache-Control: max-age=300`; the client sends `If-None-Match` and
  accepts `304`.
- Validate that `product_id` exists in a `products` table; unknown products are
  logged and skipped, never served.
- Include a `version` integer (max `updated_at`); the client stores it.

## 2. Anonymous identity

No accounts, no passwords, no email.

```
POST /v1/devices
body {"platform":"android","app_version":"0.1.0"}
201  {"player_id":"uuid","token":"<signed token>","display_name":"Elf-4821"}
```

- `player_id` = UUIDv4, `display_name` = short random handle (`Elf-####`).
- `token` = JWT (HS256, 30 days) containing `player_id`; the client stores it in
  `user://identity.json` and sends `Authorization: Bearer <token>`.
- Repeat calls with an existing token rotate nothing; a new install gets a new
  identity. Optional `POST /v1/devices/rotate` for explicit resets.
- Store `created_at`, `last_seen_at`, `app_version`, `platform`. **No PII.**

## 3. Runs and leaderboard

```
POST /v1/runs
Authorization: Bearer <token>
body {"run_id":"uuid","best_wave":23,"waves_cleared":23,"duration_s":512,
      "kills":410,"seed":183729,"checksum":"<hex>","client_version":"0.1.0",
      "mode":"normal"}
201 {"accepted":true,"rank":118,"personal_best":23}
409 {"accepted":false,"reason":"duplicate"}
422 {"accepted":false,"reason":"implausible"}
```

- `run_id` is the client's UUID and the idempotency key (`UNIQUE`).
- Reject if `best_wave < 1`, `duration_s` outside 30…7200, or
  `best_wave > duration_s / 8` (a wave takes at least ~8 s of game time);
  tune with real data.
- `checksum`: HMAC-SHA256 over `run_id|best_wave|duration_s|kills|seed` with a
  secret baked into the client build. It deters casual edits, not a determined
  attacker — mention that in the README.
- Optionally re-simulate the run from `seed` server-side before accepting; if
  that is too heavy, store `verified=false` and only show verified runs in the
  global top 100.

```
GET /v1/leaderboard?scope=global|weekly&limit=100&offset=0
200 {"entries":[{"rank":1,"name":"Elf-4821","best_wave":57,
                 "waves_cleared":57,"updated_at":"…"}],
     "me":{"rank":118,"best_wave":23},"total":10432}

GET /v1/players/{player_id}/rank   -> {"rank":118,"best_wave":23,"total":10432}
```

- Global: best run per player, sorted by `best_wave DESC, duration_s ASC`.
- Weekly: runs since Monday 00:00 UTC; same shape.
- Cap `limit` at 100; cache the top 100 for 60 s in memory.

## Data model (Alembic migration)

```sql
players(id uuid pk, display_name text not null, created_at timestamptz,
        last_seen_at timestamptz, app_version text, platform text)

runs(id uuid pk, run_id uuid unique not null, player_id uuid references players,
     best_wave int, waves_cleared int, duration_s int, kills int,
     seed bigint, checksum text, client_version text, verified bool,
     created_at timestamptz default now())
-- index (best_wave desc, duration_s asc), (player_id, created_at desc)

bundles(id text pk, product_id text not null, title text, subtitle text,
        icon text, "order" int, enabled bool default true,
        starts_at timestamptz, ends_at timestamptz, platforms text[],
        updated_at timestamptz)

products(id text pk, kind text, gems int, gold int, enabled bool)
```

## Security and operations

- Rate limit: 30 req/min per IP for `POST /v1/runs`, 10/min for `POST /v1/devices`
  (slowapi or a small in-process limiter).
- CORS: only the game origins needed; native clients need no CORS, so keep it
  empty in production.
- Log request ids, never log tokens or the full request body.
- `GET /health` → `{"status":"ok","db":"ok","version":"…"}`.
- OpenAPI docs at `/docs` in dev only (`ENV != prod`).
- Tests: bundles filtering (disabled/scheduled), device creation + token
  verification, duplicate run, implausible run, leaderboard ordering and weekly
  window, 304 on ETag.
- Dockerfile (python:3.12-slim, non-root, uvicorn workers=2) and a README with
  Neon setup, `alembic upgrade head`, and env vars.
- Seed the `products` and `bundles` tables in the first migration with the two
  offers above so the game works on day one.

## Godot client contract (already implemented on the client side)

- Bundle JSON shape is exactly the one above; the client honours `enabled`,
  `order`, `product_id`, `title`, `subtitle`.
- Client setting for the endpoint: `the_tree/bundles_url` (Project Settings).
  It expects `200` + JSON; anything else keeps the cached/offline list.
- Leaderboard endpoints are documented in `docs/LEADERBOARD.md`; the client can
  add them later behind a feature flag.

## Deliverables

1. Working repo with migrations, seed data and tests (`pytest` green).
2. `README.md`: local run, Neon setup, deploy, curl examples, bundle operations
   (add/disable/schedule offers with SQL).
3. OpenAPI examples for every endpoint.
4. A short note on the anti-cheat limits and why the client checksum is not a
   guarantee.
