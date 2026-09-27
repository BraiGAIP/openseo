# workers/python (phase 1)

Python 3.12 background workers consuming the Postgres `jobs` queue via
`claim_jobs` / `heartbeat_job` / `complete_job` / `fail_job`, deployed on
**Fly.io** (region `fra`) with process groups `rank`, `crawl`, `render`, `ai`,
`misc`. AI work is routed per analysis type to bulk (Haiku, Batch API),
standard (Sonnet) or deep (Opus) models. See `docs/ARCHITECTURE.md` §7–§9.
