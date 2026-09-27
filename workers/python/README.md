# OpenSEO workers (Python)

Background workers that consume the Postgres job queue (`public.jobs`) through the
`claim_jobs` / `heartbeat_job` / `complete_job` / `fail_job` RPCs.

| Queue | Handler | What it does |
|---|---|---|
| `rank_check` | `openseo_workers/rank/handler.py` | Fetches Google SERPs for a batch of tracked keywords, stores `keyword_positions`, refreshes search volume / CPC / competition, meters usage |

## Providers

| Provider | When | Notes |
|---|---|---|
| **DataForSEO** (`providers/dataforseo.py`) | `DATAFORSEO_LOGIN` + `DATAFORSEO_PASSWORD` set | Google Organic *advanced* results. `standard` mode (default, cheapest): `task_post` → poll `task_get/advanced/{id}`; `live` mode: `live/advanced`. `stop_crawl_on_match` stops crawling once the tracked domain is found (billed per page crawled). Keyword metrics: `keywords_data/google_ads/search_volume/live` (≤1000 keywords per call). |
| **Mock** (`providers/mock.py`) | no credentials (automatic fallback) or `SERP_PROVIDER=mock` | Deterministic demo data, zero cost. Rows are stored with `provider = 'mock'`. |

`SERP_PROVIDER=dataforseo` makes missing credentials a startup error (use it in production).

Cost/robustness details:
- SERPs are cached per day in `private.provider_cache` (shared across tenants tracking the same keyword/market/domain).
- Standard-queue task ids are persisted, so a retried job resumes polling instead of paying for new tasks.
- Keyword metrics are cached for 30 days in `private.keyword_metrics` (including "no data" answers).
- Usage is recorded per organization with idempotency keys derived from the job id (`p_enforce_quota => false`: scheduled tracking is capped by `max_keywords`, not quotas).

## Configuration

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | – (required) | Supabase: Supavisor **transaction** pooler (port 6543), user `postgres.<ref>` |
| `DB_ROLE` | `service_role` | Role assumed with `SET LOCAL ROLE` in every transaction |
| `QUEUES` / `--queues` | `rank_check` | Comma-separated |
| `WORKER_CONCURRENCY` | `4` | Jobs processed in parallel |
| `SERP_PROVIDER` | `auto` | `auto` / `dataforseo` / `mock` |
| `DATAFORSEO_LOGIN`, `DATAFORSEO_PASSWORD` | – | API credentials (HTTP Basic) |
| `DATAFORSEO_MODE` | `standard` | `standard` or `live` |
| `DATAFORSEO_STOP_ON_MATCH` | `true` | Stop SERP crawl at the tracked domain |
| `DATAFORSEO_MAX_WAIT` | `900` | Seconds to wait for queued tasks before retrying the job |
| `KEYWORD_METRICS_MAX_AGE_DAYS` | `30` | Refresh interval for search volume |

## Development

```bash
cd workers/python
python -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
ruff check . && ruff format --check .
pytest -q          # unit tests + end-to-end tests against a throw-away PostgreSQL (skipped if not installed)

# run against a database
DATABASE_URL=postgresql://... python -m openseo_workers --once     # drain the queue and exit
DATABASE_URL=postgresql://... python -m openseo_workers            # long-running worker
```

## Deploy (Fly.io)

**From GitHub (recommended):** `.github/workflows/deploy-worker.yml` deploys on every push to
`main` that touches `workers/python/`, or manually (Actions → *Deploy worker (Fly.io)* → Run workflow).
It creates the app on the first run, copies secrets from GitHub to Fly and pins one `rank` machine.

| Repository secret | |
|---|---|
| `FLY_API_TOKEN` | Fly.io → Account → Access Tokens |
| `DATABASE_URL` | Supabase → Connect → **Transaction pooler** URI (port 6543), password filled in |
| `DATAFORSEO_LOGIN`, `DATAFORSEO_PASSWORD` | DataForSEO → API Access (API password, not the site password) |

Optional repository variable `FLY_APP` if the name `openseo-workers` is taken.

**From a terminal:**

```bash
fly apps create openseo-workers            # once
fly secrets set --app openseo-workers \
  DATABASE_URL='<Supabase Dashboard → Connect → Transaction pooler URI (port 6543)>' \
  DATAFORSEO_LOGIN='…' DATAFORSEO_PASSWORD='…'
cd workers/python && fly deploy --ha=false --env SERP_PROVIDER=dataforseo
fly scale count rank=1 --app openseo-workers
fly logs --app openseo-workers             # look for "SERP provider: DataForSEO"
```
