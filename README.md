# BraiSEO

> Product name **BraiSEO** (formerly OpenSEO). Internal code names (`@openseo/*`,
> `openseo_workers`, the repository name) are unchanged.

Open-source, API-data-driven SEO platform — a SEMrush alternative — for your own
sites, client work and as a multi-tenant SaaS: rank tracking, keyword research,
competitor gap analysis, technical site audits, AI analysis and white-label
client reports.

> **Status:** foundation — architecture, database schema and tests.
> See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Stack

Next.js 16 · Supabase (Postgres 17, RLS, Auth, Storage, pg_cron) · Python workers
on Fly.io · DataForSEO / Serper · Claude API · Stripe Billing (subscriptions +
Billing Meters). UI in English with Finnish and Swedish translations.

## Layout

| Path | What |
|---|---|
| `docs/ARCHITECTURE.md` | Architecture, data & AI pipelines, billing, roadmap |
| `supabase/migrations/` | Multi-tenant schema with Row Level Security |
| `tests/db/` | Migration + RLS tests on plain PostgreSQL, schema fingerprint |
| `apps/web/` | Next.js 16 app: i18n (en/fi/sv), magic-link auth, workspaces, projects, keywords, rank dashboard |
| `workers/python/` | Python workers on Fly.io: rank tracking via DataForSEO (mock fallback), job runner, Dockerfile, fly.toml |
| `packages/shared/` | Generated Supabase types, locales, plan limit types |

## Database

```bash
./tests/db/run.sh                  # throw-away PostgreSQL: apply migrations, run RLS tests
FINGERPRINT=1 ./tests/db/run.sh    # print schema fingerprint of the tested build
```

Production: Supabase project `itxtluifqbxxrealkpfj` (eu-central-1). Migration file
names match the versions recorded in `supabase_migrations.schema_migrations`, so

```bash
supabase link --project-ref itxtluifqbxxrealkpfj
supabase db push
```

only applies new migrations. Compare `tests/db/fingerprint.sql` run against
production with the local fingerprint to detect drift.

## Deploy (Fly.io, region `fra`)

Both apps deploy from GitHub Actions when `main` changes (or manually: Actions → *Run workflow*).

| App | Workflow | Config | Cost (approx.) |
|---|---|---|---|
| Web (`braiseo-web`) | `.github/workflows/deploy-web.yml` | `apps/web/fly.toml`, `apps/web/Dockerfile` (context: repo root) | $0–4/month: sleeps when idle |
| Worker (`braiseo-workers`) | `.github/workflows/deploy-worker.yml` | `workers/python/fly.toml` | ~$3.3/month: always on |

Repository secrets: `FLY_API_TOKEN`, `DATABASE_URL`, `DATAFORSEO_LOGIN`, `DATAFORSEO_PASSWORD`,
optional `SERPER_API_KEY`. Details in `workers/python/README.md`.

After the first web deploy, add the site URL to Supabase → Authentication → URL Configuration
(*Site URL* `https://braiseo-web.fly.dev`, *Redirect URLs* `https://braiseo-web.fly.dev/**`),
otherwise magic links point to localhost.

## License

[GNU Affero General Public License v3.0](LICENSE). If you run a modified version
of BraiSEO as a network service, you must make your source code available to its
users.
