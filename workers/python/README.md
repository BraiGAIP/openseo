# workers/python (next phase)

Python 3.12 background workers consuming the Postgres `jobs` queue via
`claim_jobs` / `heartbeat_job` / `complete_job` / `fail_job`. Queues and the
provider abstraction are described in `docs/ARCHITECTURE.md` §7–§9.
