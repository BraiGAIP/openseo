# BraiSEO workers (Python)

Background workers that consume the Postgres job queue (`public.jobs`) through the
`claim_jobs` / `heartbeat_job` / `complete_job` / `fail_job` RPCs.

| Queue | Handler | What it does |
|---|---|---|
| `rank_check` | `openseo_workers/rank/handler.py` | Fetches Google SERPs for a batch of tracked keywords, stores `keyword_positions` (incl. top-10 domains), refreshes search volume / CPC / competition / keyword difficulty, records SERP change events (`rank/changes.py` → `keyword_events`), meters usage |

## Providers

| Provider | When | Notes |
|---|---|---|
| **DataForSEO** (`providers/dataforseo.py`) | `DATAFORSEO_LOGIN` + `DATAFORSEO_PASSWORD` set | Google Organic *advanced* results. `standard` mode (default, cheapest): `task_post` → poll `task_get/advanced/{id}`; `live` mode: `live/advanced`. `stop_crawl_on_match` stops crawling once the tracked domain is found (billed per page crawled). Keyword metrics: `keywords_data/google_ads/search_volume/live` (≤1000 keywords per call). |
| **Serper** (`providers/serper.py`) | `SERPER_API_KEY` set: fallback when DataForSEO fails, or the only provider without DataForSEO credentials | serper.dev Google Search API, paged 10 results at a time until the tracked domain is found (1 credit per page). Desktop results only, country-level locations, no AI Overview citations and no search volume. |
| **Mock** (`providers/mock.py`) | no credentials (automatic fallback) or `SERP_PROVIDER=mock` | Deterministic demo data, zero cost. Rows are stored with `provider = 'mock'`. |

`SERP_PROVIDER=dataforseo` makes missing credentials a startup error (use it in production).

**Fallback chain** (`providers/fallback.py`): with both DataForSEO credentials and `SERPER_API_KEY`,
a failed DataForSEO request (outage, auth, out of balance) is retried on Serper within the same job.
Queued DataForSEO tasks that are merely slow are *not* a fallback case: the job is retried later and
resumes polling. Positions keep the provider that produced them (`keyword_positions.provider`).
If the keyword volume lookup fails, positions are still tracked and volumes are retried next run.

**SERP changes:** after storing positions, each keyword is compared with its previous check
(position jumps, top-3/top-10 crossings, SERP features, AI Overview citation, ranking URL,
competitors in the top 10). Rules: `docs/ARCHITECTURE.md` §8.6. A same-day re-check replaces
that day's events.

**Manual checks** ("Check now" in the web app, `public.request_rank_check()`): jobs with
`"manual": true` skip today's SERP cache and use DataForSEO's live endpoint (several requests in
parallel) instead of the standard queue. One manual check per project per hour; the database
checks the monthly `serp_query` quota before queueing.

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
| `SERP_PROVIDER` | `auto` | `auto` / `dataforseo` / `serper` / `mock` |
| `DATAFORSEO_LOGIN`, `DATAFORSEO_PASSWORD` | – | API credentials (HTTP Basic) |
| `DATAFORSEO_MODE` | `standard` | `standard` or `live` (manual checks always use live) |
| `DATAFORSEO_STOP_ON_MATCH` | `true` | Stop SERP crawl at the tracked domain |
| `DATAFORSEO_MAX_WAIT` | `900` | Seconds to wait for queued tasks before retrying the job |
| `SERPER_API_KEY` | – | serper.dev API key (fallback provider) |
| `SERPER_COST_PER_CREDIT` | `0.001` | USD per Serper credit, for cost reporting |
| `DATAFORSEO_KEYWORD_DIFFICULTY` | `true` | Keyword difficulty from DataForSEO Labs (`bulk_keyword_difficulty`) |
| `RANK_JUMP_THRESHOLD` | `5` | Minimum move (places) reported as `position_up` / `position_down` |
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
| `SERPER_API_KEY` (optional) | serper.dev → API Key; enables the fallback provider |

Optional repository variable `FLY_APP` if the name `braiseo-workers` is taken.

**From a terminal:**

```bash
fly apps create braiseo-workers            # once
fly secrets set --app braiseo-workers \
  DATABASE_URL='<Supabase Dashboard → Connect → Transaction pooler URI (port 6543)>' \
  DATAFORSEO_LOGIN='…' DATAFORSEO_PASSWORD='…'
cd workers/python && fly deploy --ha=false --env SERP_PROVIDER=dataforseo
fly scale count rank=1 --app braiseo-workers
fly logs --app braiseo-workers             # look for "SERP provider: DataForSEO"
```
