# OpenSEO

Open-source, API-data-driven SEO platform (SEMrush alternative) for own projects,
client work and as a multi-tenant SaaS.

> **Status:** architecture + database foundation. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
>
> This folder is self-contained and is **not** connected to the Akku-Turvan Mestari
> Supabase project in the repository root. It is intended to move into its own
> repository with its own Supabase project.

## Layout

| Path | What |
|---|---|
| `docs/ARCHITECTURE.md` | Architecture, data pipeline, AI pipeline, billing, roadmap |
| `supabase/migrations/` | PostgreSQL / Supabase migrations (multi-tenant schema + RLS) |
| `tests/db/` | Migration + RLS isolation tests runnable against plain PostgreSQL |
| `apps/web/` | Next.js app (UI, public API, Stripe webhook, reports) – next phase |
| `workers/python/` | Background workers (rank checks, crawler, AI, PDF) – next phase |
| `packages/shared/` | Generated DB types, zod schemas, plan config – next phase |

## Database tests

```bash
./tests/db/run.sh   # spins up a throw-away PostgreSQL 15+ cluster, applies migrations, runs RLS tests
```

## Applying to Supabase

```bash
supabase link --project-ref <openseo-project-ref>
supabase db push                       # applies supabase/migrations
# Dashboard → Database → Extensions: enable pg_cron, then re-run the cron block
# in the migration (section 25) or schedule the jobs manually.
```
