-- =============================================================================
-- OpenSEO — core multi-tenant schema (migration 0001)
-- -----------------------------------------------------------------------------
-- Target : Supabase Postgres 15+ (tested locally against PostgreSQL 16)
-- Scope  : tenancy (organizations, members, invitations), projects, rank
--          tracking, competitor research, site audits, API keys, integrations,
--          plans / subscriptions / usage metering, job queue, AI analyses,
--          white-label reports, audit log.
--
-- Security model (see docs/ARCHITECTURE.md §5):
--   * Every tenant-owned row carries `organization_id`. It is ALWAYS derived by
--     trigger from the parent row (project / audit / keyword) — never trusted
--     from client input — so a user cannot write rows into another tenant.
--   * RLS is enabled on every table in `public`. Helper functions live in the
--     non-exposed `private` schema and are SECURITY DEFINER with an empty
--     search_path.
--   * Roles are an ordered enum (viewer < admin < owner) so policies can use
--     `role >= 'admin'`.
--   * Rows produced by workers (positions, audit issues, usage, subscriptions)
--     are read-only for end users; only `service_role` (bypasses RLS) writes.
--   * Sensitive writes (API keys, invitations, audits that cost money) happen
--     through SECURITY DEFINER RPC functions that check role + plan quota.
--   * Large time-series partitions live in `private` so PostgREST never
--     exposes a partition directly (partitions do not inherit parent RLS).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Extensions & schemas
-- -----------------------------------------------------------------------------
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_trgm  with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 1. Enum types
-- -----------------------------------------------------------------------------
-- NOTE: order matters — comparisons (>=) rely on declaration order.
create type public.org_role as enum ('viewer', 'admin', 'owner');

create type public.search_device as enum ('desktop', 'mobile');
create type public.search_engine as enum ('google', 'bing');
create type public.check_frequency as enum ('daily', 'weekly', 'monthly');
create type public.search_intent as enum ('informational', 'navigational', 'commercial', 'transactional');

create type public.audit_status as enum ('queued', 'crawling', 'analyzing', 'completed', 'failed', 'cancelled');
create type public.issue_severity as enum ('notice', 'warning', 'error');

create type public.subscription_status as enum (
  'trialing', 'active', 'past_due', 'canceled', 'incomplete',
  'incomplete_expired', 'unpaid', 'paused'
);

create type public.usage_metric as enum (
  'serp_query',        -- one ad-hoc SERP page (10 results); scheduled rank checks are
                       -- bounded by max_keywords and recorded with p_enforce_quota = false
  'keyword_lookup',    -- keyword research / metrics lookup
  'audit_page',        -- one crawled page in a site audit
  'backlink_query',    -- backlink/referring-domain request
  'ai_credit',         -- normalised LLM spend: 1 credit = USD 0.025 of model cost after batch
                       -- discount, so cheap bulk models consume fewer credits than Opus
  'api_call',          -- public REST API request authenticated with an API key
  'report_render'      -- PDF / web report generation
);

create type public.job_status as enum ('queued', 'running', 'succeeded', 'failed', 'cancelled', 'dead');
create type public.report_status as enum ('draft', 'queued', 'rendering', 'ready', 'failed');

-- -----------------------------------------------------------------------------
-- 2. Generic helpers
-- -----------------------------------------------------------------------------
create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Normalise a domain: lower-case, strip scheme, "www.", path, port.
create or replace function public.normalize_domain(p_input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(btrim(coalesce(p_input, ''))), '^[a-z][a-z0-9+.-]*://', ''),
        '^www\.', ''),
      '[/:?#].*$', ''),
    '');
$$;

-- Normalise a keyword for de-duplication: trim, lower, collapse whitespace.
create or replace function public.normalize_keyword(p_input text)
returns text
language sql
immutable
parallel safe
set search_path = ''
as $$
  select nullif(regexp_replace(lower(btrim(coalesce(p_input, ''))), '\s+', ' ', 'g'), '');
$$;

-- -----------------------------------------------------------------------------
-- 3. Plans (catalogue — public, read-only)
-- -----------------------------------------------------------------------------
create table public.plans (
  id                      text primary key,              -- 'free' | 'pro' | 'agency' | 'enterprise'
  name                    text not null,
  description             text,
  is_public               boolean not null default true,
  sort_order              smallint not null default 0,
  price_monthly_cents     integer not null default 0,
  price_yearly_cents      integer not null default 0,
  currency                text not null default 'eur',
  stripe_product_id       text unique,
  stripe_price_monthly_id text unique,
  stripe_price_yearly_id  text unique,
  -- Hard caps (-1 = unlimited) + monthly quotas + feature flags. Shape:
  -- { "max_projects":5, "max_keywords":500, "max_seats":3,
  --   "max_competitors_per_project":10, "max_pages_per_audit":5000,
  --   "rank_check_min_frequency":"daily", "rank_depth":20,
  --   "api_access":true, "white_label":false, "custom_domain":false,
  --   "overage_enabled":true,
  --   "quota": { "serp_query":20000, "keyword_lookup":3000, "audit_page":20000,
  --              "backlink_query":500, "ai_credit":300, "api_call":10000,
  --              "report_render":50 } }
  limits                  jsonb not null default '{}'::jsonb,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);

create trigger plans_touch before update on public.plans
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 4. Organizations & membership
-- -----------------------------------------------------------------------------
create table public.organizations (
  id                   uuid primary key default gen_random_uuid(),
  name                 text not null check (char_length(name) between 1 and 120),
  slug                 text not null unique
                         check (slug ~ '^[a-z0-9](?:[a-z0-9-]{0,48}[a-z0-9])?$'),
  is_personal          boolean not null default false,
  -- Client work: an agency can model each client as its own organization or as
  -- projects inside the agency organization (see projects.client_name).
  billing_email        text check (billing_email = lower(billing_email)),
  country_code         char(2),
  vat_id               text,
  stripe_customer_id   text unique,                 -- written by server only
  -- White-label branding (used by report generator when plan.white_label = true)
  brand_name           text,
  brand_logo_path      text,                        -- storage: branding/<org_id>/logo.png
  brand_primary_color  text check (brand_primary_color ~ '^#[0-9a-fA-F]{6}$'),
  brand_accent_color   text check (brand_accent_color  ~ '^#[0-9a-fA-F]{6}$'),
  report_footer_text   text,
  custom_report_domain text unique check (custom_report_domain = lower(custom_report_domain)),  -- e.g. reports.agency.fi (CNAME)
  default_locale       text not null default 'en' check (default_locale in ('en', 'fi', 'sv')),
  settings             jsonb not null default '{}'::jsonb,
  created_by           uuid default auth.uid() references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create trigger organizations_touch before update on public.organizations
  for each row execute function private.touch_updated_at();

create table public.organization_members (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  role            public.org_role not null default 'viewer',
  invited_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index organization_members_user_idx on public.organization_members (user_id);

create trigger organization_members_touch before update on public.organization_members
  for each row execute function private.touch_updated_at();

create table public.organization_invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email           text not null check (email = lower(email)),
  role            public.org_role not null default 'viewer',
  token_hash      text not null unique,             -- sha256(token); plaintext only e-mailed
  invited_by      uuid references auth.users (id) on delete set null,
  expires_at      timestamptz not null default now() + interval '7 days',
  accepted_at     timestamptz,
  accepted_by     uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now()
);

create unique index organization_invitations_pending_uidx
  on public.organization_invitations (organization_id, email)
  where accepted_at is null;

-- -----------------------------------------------------------------------------
-- 5. Authorization helpers (used by RLS policies)
-- -----------------------------------------------------------------------------
create or replace function private.has_org_role(p_org_id uuid, p_min_role public.org_role default 'viewer')
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_org_id
      and m.user_id = (select auth.uid())
      and m.role >= p_min_role
  );
$$;

create or replace function private.current_role_in(p_org_id uuid)
returns public.org_role
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.organization_members m
  where m.organization_id = p_org_id
    and m.user_id = (select auth.uid());
$$;

-- Safe text → uuid (null instead of an error), used by storage policies.
create or replace function private.try_uuid(p_text text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_text::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

grant execute on function private.try_uuid(text) to authenticated, service_role;

revoke all on function private.has_org_role(uuid, public.org_role) from public;
revoke all on function private.current_role_in(uuid) from public;
grant execute on function private.has_org_role(uuid, public.org_role) to authenticated, service_role;
grant execute on function private.current_role_in(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6. Subscriptions & plan limits
-- -----------------------------------------------------------------------------
create table public.subscriptions (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations (id) on delete cascade,
  plan_id                text not null references public.plans (id),
  status                 public.subscription_status not null,
  billing_interval       text not null default 'month' check (billing_interval in ('month', 'year')),
  stripe_customer_id     text,
  stripe_subscription_id text unique,
  seats                  integer not null default 1 check (seats > 0),
  current_period_start   timestamptz,
  current_period_end     timestamptz,
  cancel_at_period_end   boolean not null default false,
  canceled_at            timestamptz,
  trial_end              timestamptz,
  limit_overrides        jsonb not null default '{}'::jsonb,  -- per-customer deals (enterprise)
  metadata               jsonb not null default '{}'::jsonb,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- At most one "live" subscription per organization.
create unique index subscriptions_one_live_per_org
  on public.subscriptions (organization_id)
  where status in ('trialing', 'active', 'past_due', 'unpaid', 'paused', 'incomplete');

create trigger subscriptions_touch before update on public.subscriptions
  for each row execute function private.touch_updated_at();

-- Effective limits = plan.limits deep-merged with subscription.limit_overrides.
-- Falls back to the 'free' plan when no live subscription exists.
create or replace function private.org_limits(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select p.limits
             || (s.limit_overrides - 'quota')
             || jsonb_build_object('quota',
                  coalesce(p.limits -> 'quota', '{}'::jsonb)
                  || coalesce(s.limit_overrides -> 'quota', '{}'::jsonb))
      from public.subscriptions s
      join public.plans p on p.id = s.plan_id
      where s.organization_id = p_org_id
        and s.status in ('trialing', 'active', 'past_due')   -- past_due keeps access during dunning
      order by s.created_at desc
      limit 1
    ),
    (select limits from public.plans where id = 'free'),
    '{}'::jsonb
  );
$$;

-- Numeric cap, -1 / missing = unlimited (returns null).
create or replace function private.org_limit(p_org_id uuid, p_key text)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select nullif((private.org_limits(p_org_id) ->> p_key)::bigint, -1);
$$;

-- Start of the current billing period (Stripe period, else calendar month).
create or replace function private.org_period_start(p_org_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select s.current_period_start
      from public.subscriptions s
      where s.organization_id = p_org_id
        and s.status in ('trialing', 'active', 'past_due')
        and s.current_period_start <= now()
        and (s.current_period_end is null or s.current_period_end > now())
      order by s.created_at desc
      limit 1
    ),
    date_trunc('month', now())
  );
$$;

revoke all on function private.org_limits(uuid) from public;
revoke all on function private.org_limit(uuid, text) from public;
revoke all on function private.org_period_start(uuid) from public;
grant execute on function private.org_limits(uuid) to authenticated, service_role;
grant execute on function private.org_limit(uuid, text) to authenticated, service_role;
grant execute on function private.org_period_start(uuid) to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7. Projects
-- -----------------------------------------------------------------------------
create table public.projects (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete cascade,
  name              text not null check (char_length(name) between 1 and 120),
  domain            text not null check (domain = public.normalize_domain(domain)),
  root_url          text not null,                          -- canonical start URL for crawls
  -- Default search context for tracking/research
  location_code     integer not null default 2840,          -- DataForSEO location code (2840 = US, 2826 = UK, 2246 = FI, 2752 = SE)
  language_code     text not null default 'en',
  search_engine     public.search_engine not null default 'google',
  default_device    public.search_device not null default 'desktop',
  -- Client-work metadata (agency use-case)
  is_client_project boolean not null default false,
  client_name       text,
  client_contact    text,
  tags              text[] not null default '{}',
  settings          jsonb not null default '{}'::jsonb,     -- crawl rules, excluded paths, etc.
  archived_at       timestamptz,
  created_by        uuid default auth.uid() references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (organization_id, domain),
  unique (id, organization_id)                              -- composite FK target
);

create index projects_org_idx on public.projects (organization_id) where archived_at is null;

create trigger projects_touch before update on public.projects
  for each row execute function private.touch_updated_at();

-- Derive organization_id from the project (child tables of projects).
create or replace function private.set_org_from_project()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select p.organization_id into new.organization_id
  from public.projects p
  where p.id = new.project_id;

  if new.organization_id is null then
    raise exception 'project % not found', new.project_id using errcode = '23503';
  end if;
  return new;
end;
$$;

-- Plan hard-cap enforcement. TG_ARGV[0] = limit key.
create or replace function private.enforce_plan_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key   text := tg_argv[0];
  v_limit bigint;
  v_count bigint;
begin
  v_limit := private.org_limit(new.organization_id, v_key);
  if v_limit is null then
    return new;                                   -- unlimited
  end if;

  -- Serialise concurrent inserts for the same org + limit.
  perform pg_advisory_xact_lock(hashtextextended(new.organization_id::text || ':' || v_key, 0));

  case tg_table_name
    when 'projects' then
      select count(*) into v_count from public.projects
      where organization_id = new.organization_id and archived_at is null;
    when 'keyword_tracking' then
      select count(*) into v_count from public.keyword_tracking
      where organization_id = new.organization_id and is_active;
    when 'competitor_domains' then
      select count(*) into v_count from public.competitor_domains
      where project_id = new.project_id;
    when 'organization_members' then
      select count(*) into v_count from public.organization_members
      where organization_id = new.organization_id;
    else
      raise exception 'enforce_plan_limit: unsupported table %', tg_table_name;
  end case;

  if v_count >= v_limit then
    raise exception 'plan_limit_exceeded:%', v_key
      using errcode = 'P0001',
            hint = format('Current plan allows %s. Upgrade to add more.', v_limit);
  end if;
  return new;
end;
$$;

create trigger b_projects_limit before insert on public.projects
  for each row execute function private.enforce_plan_limit('max_projects');

create trigger b_members_limit before insert on public.organization_members
  for each row execute function private.enforce_plan_limit('max_seats');

-- -----------------------------------------------------------------------------
-- 8. Keyword tracking & position history
-- -----------------------------------------------------------------------------
create table public.keyword_tracking (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null,
  project_id          uuid not null,
  keyword             text not null check (char_length(keyword) between 1 and 300),
  keyword_normalized  text generated always as (public.normalize_keyword(keyword)) stored,
  location_code       integer not null,
  language_code       text not null,
  search_engine       public.search_engine not null default 'google',
  device              public.search_device not null default 'desktop',
  target_url          text,                                   -- URL we want to rank
  tags                text[] not null default '{}',
  -- Market metrics (refreshed monthly from provider; shared cache in private.keyword_metrics)
  search_volume       integer,
  keyword_difficulty  smallint check (keyword_difficulty between 0 and 100),
  cpc_usd             numeric(10, 2),
  competition         numeric(4, 3) check (competition between 0 and 1),
  search_intent       public.search_intent,
  monthly_searches    jsonb,                                  -- [{year, month, volume}]
  metrics_updated_at  timestamptz,
  -- Scheduling
  frequency           public.check_frequency not null default 'daily',
  depth               smallint not null default 20 check (depth in (10, 20, 30, 50, 100)),
  is_active           boolean not null default true,
  next_check_at       timestamptz not null default now(),
  -- Denormalised latest snapshot (maintained by trigger on keyword_positions)
  current_position    smallint,
  previous_position   smallint,
  best_position       smallint,
  current_url         text,
  serp_features       text[],
  last_check_date     date,
  created_by          uuid default auth.uid() references auth.users (id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade,
  unique (project_id, keyword_normalized, location_code, language_code, search_engine, device)
);

create index keyword_tracking_org_idx on public.keyword_tracking (organization_id);
create index keyword_tracking_due_idx on public.keyword_tracking (next_check_at) where is_active;
create index keyword_tracking_tags_idx on public.keyword_tracking using gin (tags);
create index keyword_tracking_kw_trgm_idx on public.keyword_tracking
  using gin (keyword_normalized extensions.gin_trgm_ops);

create trigger a_keyword_tracking_org before insert or update of project_id, organization_id
  on public.keyword_tracking
  for each row execute function private.set_org_from_project();

create trigger b_keyword_tracking_limit before insert on public.keyword_tracking
  for each row execute function private.enforce_plan_limit('max_keywords');

create trigger keyword_tracking_touch before update on public.keyword_tracking
  for each row execute function private.touch_updated_at();

-- Default search context from the project when omitted.
create or replace function private.keyword_defaults_from_project()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.location_code is null or new.language_code is null then
    select coalesce(new.location_code, p.location_code),
           coalesce(new.language_code, p.language_code)
      into new.location_code, new.language_code
    from public.projects p where p.id = new.project_id;
  end if;
  return new;
end;
$$;

create trigger a0_keyword_tracking_defaults before insert on public.keyword_tracking
  for each row execute function private.keyword_defaults_from_project();

-- One row per keyword per day. Range-partitioned by month; partitions live in
-- the `private` schema so they are never exposed via PostgREST.
create table public.keyword_positions (
  keyword_id        uuid not null references public.keyword_tracking (id) on delete cascade,
  check_date        date not null,
  organization_id   uuid not null,
  project_id        uuid not null,
  checked_at        timestamptz not null default now(),
  position          smallint check (position between 1 and 100),   -- null = not in checked depth
  url               text,
  title             text,
  serp_features     text[] not null default '{}',   -- featured_snippet, local_pack, ai_overview, paa, ...
  owns_ai_overview  boolean,                          -- domain cited in AI Overview / answer box
  depth_checked     smallint not null default 20,
  estimated_traffic numeric(12, 2),
  provider          text not null,                    -- 'dataforseo' | 'serper' | 'valueserp' | 'scraper'
  raw_ref           text,                             -- storage path / provider task id for replay
  primary key (keyword_id, check_date)
) partition by range (check_date);

create index keyword_positions_project_date_idx on public.keyword_positions (project_id, check_date);
create index keyword_positions_org_idx on public.keyword_positions (organization_id);

create table private.keyword_positions_default
  partition of public.keyword_positions default;

create or replace function private.set_scope_from_keyword()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select k.organization_id, k.project_id
    into new.organization_id, new.project_id
  from public.keyword_tracking k
  where k.id = new.keyword_id;

  if new.organization_id is null then
    raise exception 'keyword % not found', new.keyword_id using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger a_keyword_positions_scope before insert on public.keyword_positions
  for each row execute function private.set_scope_from_keyword();

-- Keep the snapshot on keyword_tracking fresh.
create or replace function private.update_keyword_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.keyword_tracking k
     set previous_position = case when k.last_check_date is distinct from new.check_date
                                  then k.current_position else k.previous_position end,
         current_position  = new.position,
         best_position     = case when new.position is null then k.best_position
                                  else least(coalesce(k.best_position, new.position), new.position) end,
         current_url       = new.url,
         serp_features     = new.serp_features,
         last_check_date   = new.check_date
   where k.id = new.keyword_id
     and (k.last_check_date is null or new.check_date >= k.last_check_date);
  return null;
end;
$$;

create trigger z_keyword_positions_snapshot after insert or update on public.keyword_positions
  for each row execute function private.update_keyword_snapshot();

-- Monthly partition maintenance (call from pg_cron; idempotent).
create or replace function private.ensure_keyword_position_partitions(p_months_ahead int default 3)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_start date := (date_trunc('month', now()) - interval '1 month')::date;
  v_from  date;
  v_to    date;
  v_name  text;
begin
  for i in 0 .. p_months_ahead + 1 loop
    v_from := (v_start + make_interval(months => i))::date;
    v_to   := (v_from + interval '1 month')::date;
    v_name := 'keyword_positions_' || to_char(v_from, 'YYYY_MM');
    if to_regclass('private.' || v_name) is null then
      execute format(
        'create table private.%I partition of public.keyword_positions for values from (%L) to (%L)',
        v_name, v_from, v_to);
    end if;
  end loop;
end;
$$;

do $$ begin perform private.ensure_keyword_position_partitions(3); end $$;

-- -----------------------------------------------------------------------------
-- 9. Competitor research
-- -----------------------------------------------------------------------------
create table public.competitor_domains (
  id                   uuid primary key default gen_random_uuid(),
  organization_id      uuid not null,
  project_id           uuid not null,
  domain               text not null check (domain = public.normalize_domain(domain)),
  label                text,
  source               text not null default 'manual' check (source in ('manual', 'auto_discovered')),
  -- Latest aggregate snapshot (refreshed by worker)
  common_keywords      integer,
  organic_keywords     integer,
  organic_traffic_est  numeric(14, 2),
  visibility_score     numeric(6, 3),
  referring_domains    integer,
  metrics_updated_at   timestamptz,
  created_by           uuid default auth.uid() references auth.users (id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade,
  unique (project_id, domain),
  unique (id, organization_id)
);

create index competitor_domains_org_idx on public.competitor_domains (organization_id);

create trigger a_competitor_domains_org before insert or update of project_id, organization_id
  on public.competitor_domains
  for each row execute function private.set_org_from_project();

create trigger b_competitor_domains_limit before insert on public.competitor_domains
  for each row execute function private.enforce_plan_limit('max_competitors_per_project');

create trigger competitor_domains_touch before update on public.competitor_domains
  for each row execute function private.touch_updated_at();

-- Keywords a competitor ranks for ("reverse engineering"), one snapshot per date.
create table public.competitor_keywords (
  id                    bigint generated always as identity primary key,
  organization_id       uuid not null,
  project_id            uuid not null,
  competitor_domain_id  uuid not null references public.competitor_domains (id) on delete cascade,
  snapshot_date         date not null default current_date,
  keyword               text not null,
  keyword_normalized    text generated always as (public.normalize_keyword(keyword)) stored,
  location_code         integer not null,
  language_code         text not null,
  position              smallint,
  url                   text,
  search_volume         integer,
  keyword_difficulty    smallint,
  cpc_usd               numeric(10, 2),
  search_intent         public.search_intent,
  estimated_traffic     numeric(12, 2),
  our_position          smallint,              -- where the project ranks (null = not ranking)
  gap_type              text generated always as (
                          case
                            when our_position is null then 'missing'
                            when position is not null and our_position > position then 'weak'
                            else 'strong'
                          end) stored,
  unique (competitor_domain_id, keyword_normalized, location_code, language_code, snapshot_date)
);

create index competitor_keywords_project_idx on public.competitor_keywords (project_id, snapshot_date desc);
create index competitor_keywords_gap_idx on public.competitor_keywords (project_id, gap_type, search_volume desc);
create index competitor_keywords_org_idx on public.competitor_keywords (organization_id);

create or replace function private.set_scope_from_competitor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select c.organization_id, c.project_id
    into new.organization_id, new.project_id
  from public.competitor_domains c
  where c.id = new.competitor_domain_id;

  if new.organization_id is null then
    raise exception 'competitor % not found', new.competitor_domain_id using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger a_competitor_keywords_scope before insert or update of competitor_domain_id
  on public.competitor_keywords
  for each row execute function private.set_scope_from_competitor();

-- -----------------------------------------------------------------------------
-- 10. Site audits
-- -----------------------------------------------------------------------------
-- Catalogue of checks (code-owned, seeded below; extended by later migrations).
create table public.audit_issue_types (
  code         text primary key,                        -- e.g. 'missing_title'
  category     text not null,                           -- crawlability | on_page | performance | links | international | ai_readiness
  severity     public.issue_severity not null,
  title        text not null,
  description  text not null,
  how_to_fix   text not null,
  weight       smallint not null default 1 check (weight between 0 and 10),  -- health-score weight
  is_active    boolean not null default true
);

create table public.site_audits (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null,
  project_id       uuid not null,
  status           public.audit_status not null default 'queued',
  -- { max_pages, max_depth, render_js, respect_robots, user_agent, include[], exclude[], check_external_links }
  config           jsonb not null default '{}'::jsonb,
  pages_limit      integer not null default 500 check (pages_limit > 0),
  pages_crawled    integer not null default 0,
  pages_indexable  integer,
  health_score     smallint check (health_score between 0 and 100),
  errors_count     integer not null default 0,
  warnings_count   integer not null default 0,
  notices_count    integer not null default 0,
  summary          jsonb not null default '{}'::jsonb,   -- per-category counts, CWV aggregates
  report_html_path text,                                 -- storage: reports/<org_id>/audits/<id>.html
  report_pdf_path  text,
  error_message    text,
  triggered_by     uuid references auth.users (id) on delete set null,
  trigger_source   text not null default 'manual' check (trigger_source in ('manual', 'schedule', 'api')),
  queued_at        timestamptz not null default now(),
  started_at       timestamptz,
  finished_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade
);

create index site_audits_project_idx on public.site_audits (project_id, created_at desc);
create index site_audits_org_idx on public.site_audits (organization_id);

create trigger a_site_audits_org before insert or update of project_id, organization_id
  on public.site_audits
  for each row execute function private.set_org_from_project();

create trigger site_audits_touch before update on public.site_audits
  for each row execute function private.touch_updated_at();

create table public.audit_pages (
  id                bigint generated always as identity primary key,
  audit_id          uuid not null references public.site_audits (id) on delete cascade,
  organization_id   uuid not null,
  url               text not null,
  status_code       smallint,
  content_type      text,
  depth             smallint,
  title             text,
  meta_description  text,
  h1                text,
  canonical_url     text,
  is_indexable      boolean,
  word_count        integer,
  internal_links    integer,
  external_links    integer,
  response_ms       integer,
  page_size_bytes   integer,
  lcp_ms            integer,
  cls               numeric(6, 3),
  inp_ms            integer,
  structured_data   text[],                -- schema.org types found
  content_hash      text,                  -- duplicate detection
  crawled_at        timestamptz not null default now(),
  unique (audit_id, url)
);

create index audit_pages_org_idx on public.audit_pages (organization_id);

create table public.audit_issues (
  id               bigint generated always as identity primary key,
  audit_id         uuid not null references public.site_audits (id) on delete cascade,
  organization_id  uuid not null,
  page_id          bigint references public.audit_pages (id) on delete cascade,
  issue_code       text not null references public.audit_issue_types (code),
  severity         public.issue_severity not null,
  url              text,
  details          jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now()
);

create index audit_issues_audit_idx on public.audit_issues (audit_id, severity, issue_code);
create index audit_issues_org_idx on public.audit_issues (organization_id);

create or replace function private.set_org_from_audit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select a.organization_id into new.organization_id
  from public.site_audits a
  where a.id = new.audit_id;

  if new.organization_id is null then
    raise exception 'audit % not found', new.audit_id using errcode = '23503';
  end if;
  return new;
end;
$$;

create trigger a_audit_pages_org before insert on public.audit_pages
  for each row execute function private.set_org_from_audit();
create trigger a_audit_issues_org before insert on public.audit_issues
  for each row execute function private.set_org_from_audit();

-- -----------------------------------------------------------------------------
-- 11. API keys (inbound) & integrations (outbound credentials)
-- -----------------------------------------------------------------------------
create table public.api_keys (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  project_id       uuid,                                   -- optional: key scoped to one client project
  name             text not null check (char_length(name) between 1 and 80),
  key_prefix       text not null,                          -- first chars, shown in UI ("oseo_3f9a1c")
  key_hash         text not null unique,                   -- sha256(hex) of full key; plaintext never stored
  scopes           text[] not null default '{read}',
  rate_limit_per_min integer not null default 60,
  last_used_at     timestamptz,
  last_used_ip     inet,
  expires_at       timestamptz,
  revoked_at       timestamptz,
  created_by       uuid default auth.uid() references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade,
  check (scopes <@ array['read', 'keywords:write', 'audits:run', 'competitors:write', 'reports:read', 'reports:write']::text[])
);

create index api_keys_org_idx on public.api_keys (organization_id) where revoked_at is null;

-- Third-party connections (Google Search Console, GA4, BYOK DataForSEO, Slack, webhooks).
-- Secrets live in Supabase Vault; this table only references them.
create table public.integrations (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations (id) on delete cascade,
  project_id       uuid,
  provider         text not null check (provider in (
                     'google_search_console', 'google_analytics', 'google_business_profile',
                     'dataforseo_byok', 'serper_byok', 'slack', 'webhook', 'looker_studio')),
  display_name     text,
  status           text not null default 'pending' check (status in ('pending', 'active', 'error', 'revoked')),
  config           jsonb not null default '{}'::jsonb,     -- non-secret settings (property id, channel...)
  vault_secret_id  uuid,                                   -- vault.secrets.id — server-side only
  last_synced_at   timestamptz,
  last_error       text,
  created_by       uuid default auth.uid() references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade
);

create index integrations_org_idx on public.integrations (organization_id);

create trigger integrations_touch before update on public.integrations
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 12. Usage metering (internal ledger → Stripe Billing Meters)
-- -----------------------------------------------------------------------------
create table public.usage_records (
  id                  bigint generated always as identity primary key,
  organization_id     uuid not null references public.organizations (id) on delete cascade,
  project_id          uuid references public.projects (id) on delete set null,
  metric              public.usage_metric not null,
  quantity            integer not null check (quantity > 0),
  occurred_at         timestamptz not null default now(),
  source              text not null default 'app' check (source in ('app', 'api', 'worker', 'schedule')),
  api_key_id          uuid references public.api_keys (id) on delete set null,
  job_id              bigint,
  provider            text,                              -- upstream provider for COGS tracking
  provider_cost_usd   numeric(12, 6),                    -- what it cost us (margin analytics)
  idempotency_key     text not null unique,              -- also used as Stripe meter event identifier
  stripe_reported_at  timestamptz,                       -- null = not yet pushed to Stripe
  metadata            jsonb not null default '{}'::jsonb
);

create index usage_records_org_metric_time_idx
  on public.usage_records (organization_id, metric, occurred_at desc);
create index usage_records_unreported_idx
  on public.usage_records (occurred_at) where stripe_reported_at is null;

-- -----------------------------------------------------------------------------
-- 13. Job queue (Postgres-native, FOR UPDATE SKIP LOCKED)
-- -----------------------------------------------------------------------------
create table public.jobs (
  id               bigint generated always as identity primary key,
  queue            text not null check (queue in (
                     'rank_check', 'keyword_metrics', 'site_audit', 'competitor_discovery',
                     'competitor_keywords', 'backlinks', 'ai_analysis', 'report_render',
                     'stripe_usage_sync', 'integration_sync', 'maintenance')),
  organization_id  uuid references public.organizations (id) on delete cascade,
  project_id       uuid references public.projects (id) on delete cascade,
  payload          jsonb not null default '{}'::jsonb,
  status           public.job_status not null default 'queued',
  priority         smallint not null default 100,        -- lower runs first (paid plans get lower)
  attempts         integer not null default 0,
  max_attempts     integer not null default 5,
  run_after        timestamptz not null default now(),
  dedupe_key       text,
  locked_by        text,
  locked_at        timestamptz,
  heartbeat_at     timestamptz,
  progress         numeric(5, 2) check (progress between 0 and 100),
  result           jsonb,
  last_error       text,
  created_at       timestamptz not null default now(),
  finished_at      timestamptz
);

create index jobs_claim_idx on public.jobs (queue, priority, run_after) where status = 'queued';
create index jobs_running_idx on public.jobs (heartbeat_at) where status = 'running';
create index jobs_org_idx on public.jobs (organization_id, created_at desc);
create unique index jobs_dedupe_active_uidx on public.jobs (dedupe_key)
  where dedupe_key is not null and status in ('queued', 'running');

-- -----------------------------------------------------------------------------
-- 14. AI analyses & white-label reports
-- -----------------------------------------------------------------------------
create table public.ai_analyses (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null,
  project_id        uuid not null,
  kind              text not null check (kind in (
                      'content_quality', 'competitor_gap', 'audit_summary', 'keyword_clustering',
                      'serp_intent', 'content_brief', 'ai_search_visibility', 'report_narrative')),
  status            public.job_status not null default 'queued',
  subject_ref       jsonb not null default '{}'::jsonb,   -- {"audit_id":..} | {"url":..} | {"keyword_ids":[..]}
  input_hash        text,                                 -- cache key: sha256(prompt_version + inputs)
  model             text,
  model_tier        text check (model_tier in ('bulk', 'standard', 'deep')),
  used_batch_api    boolean not null default false,
  prompt_version    text,
  output            jsonb,                                -- structured (JSON-schema validated) result
  output_markdown   text,
  input_tokens      integer,
  output_tokens     integer,
  cache_read_tokens integer,
  cost_usd          numeric(10, 6),
  requested_by      uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  completed_at      timestamptz,
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade
);

create index ai_analyses_project_idx on public.ai_analyses (project_id, kind, created_at desc);
create index ai_analyses_input_hash_idx on public.ai_analyses (input_hash) where status = 'succeeded';

create trigger a_ai_analyses_org before insert or update of project_id, organization_id
  on public.ai_analyses
  for each row execute function private.set_org_from_project();

create table public.reports (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null,
  project_id        uuid not null,
  title             text not null,
  report_type       text not null check (report_type in (
                      'seo_overview', 'rank_tracking', 'site_audit', 'competitor', 'custom')),
  status            public.report_status not null default 'draft',
  period_start      date,
  period_end        date,
  sections          jsonb not null default '[]'::jsonb,   -- ordered widget config
  branding          jsonb not null default '{}'::jsonb,   -- snapshot of org branding at render time
  white_label       boolean not null default false,
  locale            text not null default 'en' check (locale in ('en', 'fi', 'sv')),
  html_path         text,
  pdf_path          text,
  share_token_hash  text unique,                          -- public link: /r/<token>
  share_expires_at  timestamptz,
  schedule_cron     text,                                 -- e.g. monthly client report
  recipients        text[] not null default '{}',
  last_rendered_at  timestamptz,
  created_by        uuid default auth.uid() references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade
);

create index reports_project_idx on public.reports (project_id, created_at desc);

create trigger a_reports_org before insert or update of project_id, organization_id
  on public.reports
  for each row execute function private.set_org_from_project();

create trigger reports_touch before update on public.reports
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- 15. Audit log (security-relevant actions)
-- -----------------------------------------------------------------------------
create table public.audit_log (
  id               bigint generated always as identity primary key,
  organization_id  uuid references public.organizations (id) on delete cascade,
  actor_user_id    uuid,
  actor_api_key_id uuid,
  action           text not null,          -- 'api_key.created', 'member.role_changed', ...
  target_type      text,
  target_id        text,
  metadata         jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now()
);

create index audit_log_org_idx on public.audit_log (organization_id, created_at desc);

create or replace function private.log_action(
  p_org uuid, p_action text, p_target_type text, p_target_id text, p_metadata jsonb default '{}'::jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.audit_log (organization_id, actor_user_id, action, target_type, target_id, metadata)
  values (p_org, (select auth.uid()), p_action, p_target_type, p_target_id, coalesce(p_metadata, '{}'::jsonb));
$$;

-- -----------------------------------------------------------------------------
-- 16. Private shared caches (not tenant data; never exposed to clients)
-- -----------------------------------------------------------------------------
-- Keyword market metrics are public market data → shared across tenants to
-- cut provider cost. Access is metered through the API layer.
create table private.keyword_metrics (
  keyword_normalized text not null,
  location_code      integer not null,
  language_code      text not null,
  search_volume      integer,
  keyword_difficulty smallint,
  cpc_usd            numeric(10, 2),
  competition        numeric(4, 3),
  search_intent      public.search_intent,
  monthly_searches   jsonb,
  serp_features      text[],
  provider           text not null,
  fetched_at         timestamptz not null default now(),
  primary key (keyword_normalized, location_code, language_code)
);

-- Raw provider response cache (dedupes identical SERP/labs calls across tenants).
create table private.provider_cache (
  cache_key    text primary key,                    -- sha256(provider|endpoint|canonical params)
  provider     text not null,
  endpoint     text not null,
  response     jsonb not null,
  cost_usd     numeric(12, 6),
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null
);

create index provider_cache_expiry_idx on private.provider_cache (expires_at);

-- -----------------------------------------------------------------------------
-- 17. Membership integrity
-- -----------------------------------------------------------------------------
-- Never leave an organization without an owner.
create or replace function private.protect_last_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining int;
begin
  if old.role = 'owner'
     and (tg_op = 'DELETE' or new.role <> 'owner') then
    -- Cascade from organization delete: org row already gone → allow.
    if not exists (select 1 from public.organizations o where o.id = old.organization_id) then
      return coalesce(new, old);
    end if;
    select count(*) into v_remaining
    from public.organization_members
    where organization_id = old.organization_id
      and role = 'owner'
      and user_id <> old.user_id;
    if v_remaining = 0 then
      raise exception 'organization must keep at least one owner' using errcode = 'P0001';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;

create trigger organization_members_last_owner
  before update of role or delete on public.organization_members
  for each row execute function private.protect_last_owner();

-- Admins may not promote anyone to owner nor touch owners; only owners can.
create or replace function private.guard_member_role_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.org_role;
begin
  if (select auth.uid()) is null then
    return new;                                   -- service_role / migrations
  end if;
  v_actor := private.current_role_in(new.organization_id);
  if v_actor is distinct from 'owner'
     and (new.role = 'owner' or old.role = 'owner') then
    raise exception 'only owners can grant or revoke the owner role' using errcode = '42501';
  end if;
  if new.user_id <> old.user_id or new.organization_id <> old.organization_id then
    raise exception 'membership identity is immutable' using errcode = '42501';
  end if;
  perform private.log_action(new.organization_id, 'member.role_changed', 'user', new.user_id::text,
    jsonb_build_object('from', old.role, 'to', new.role));
  return new;
end;
$$;

create trigger organization_members_guard_role
  before update on public.organization_members
  for each row execute function private.guard_member_role_change();

-- -----------------------------------------------------------------------------
-- 18. RPC functions for authenticated users
-- -----------------------------------------------------------------------------
-- Create an organization and make the caller its owner (atomic).
create or replace function public.create_organization(p_name text, p_slug text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_id   uuid;
  v_slug text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  v_slug := coalesce(nullif(lower(btrim(p_slug)), ''),
                     trim(both '-' from regexp_replace(lower(p_name), '[^a-z0-9]+', '-', 'g')));
  if v_slug is null or v_slug = '' then
    v_slug := 'org';
  end if;
  v_slug := left(v_slug, 40);
  if exists (select 1 from public.organizations where slug = v_slug) then
    v_slug := v_slug || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
  end if;

  insert into public.organizations (name, slug, created_by)
  values (p_name, v_slug, v_uid)
  returning id into v_id;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_id, v_uid, 'owner');

  perform private.log_action(v_id, 'organization.created', 'organization', v_id::text);
  return v_id;
end;
$$;

-- Invite a member; returns the plaintext token ONCE (app e-mails the link).
create or replace function public.invite_member(p_org_id uuid, p_email text, p_role public.org_role default 'viewer')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_seats bigint;
  v_used  bigint;
begin
  if not private.has_org_role(p_org_id, 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if p_role = 'owner' and not private.has_org_role(p_org_id, 'owner') then
    raise exception 'only owners can invite owners' using errcode = '42501';
  end if;

  v_seats := private.org_limit(p_org_id, 'max_seats');
  if v_seats is not null then
    select (select count(*) from public.organization_members where organization_id = p_org_id)
         + (select count(*) from public.organization_invitations
             where organization_id = p_org_id and accepted_at is null and expires_at > now())
      into v_used;
    if v_used >= v_seats then
      raise exception 'plan_limit_exceeded:max_seats' using errcode = 'P0001';
    end if;
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  delete from public.organization_invitations
   where organization_id = p_org_id and email = lower(btrim(p_email)) and accepted_at is null;

  insert into public.organization_invitations (organization_id, email, role, token_hash, invited_by)
  values (p_org_id, lower(btrim(p_email)), p_role,
          encode(extensions.digest(v_token, 'sha256'), 'hex'), (select auth.uid()));

  perform private.log_action(p_org_id, 'member.invited', 'email', p_email, jsonb_build_object('role', p_role));
  return v_token;
end;
$$;

-- Accept an invitation. The invite e-mail must match the signed-in user.
create or replace function public.accept_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_email text := lower((select auth.jwt()) ->> 'email');
  v_inv   public.organization_invitations;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into v_inv
  from public.organization_invitations
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and accepted_at is null
    and expires_at > now()
  for update;

  if v_inv.id is null or v_inv.email is distinct from v_email then
    raise exception 'invalid or expired invitation' using errcode = '22023';
  end if;

  insert into public.organization_members (organization_id, user_id, role, invited_by)
  values (v_inv.organization_id, v_uid, v_inv.role, v_inv.invited_by)
  on conflict (organization_id, user_id) do nothing;

  update public.organization_invitations
     set accepted_at = now(), accepted_by = v_uid
   where id = v_inv.id;

  perform private.log_action(v_inv.organization_id, 'member.joined', 'user', v_uid::text);
  return v_inv.organization_id;
end;
$$;

-- Create an API key. Returns the plaintext key ONCE.
create or replace function public.create_api_key(
  p_org_id     uuid,
  p_name       text,
  p_scopes     text[] default array['read'],
  p_project_id uuid default null,
  p_expires_at timestamptz default null)
returns table (id uuid, api_key text, key_prefix text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key    text;
  v_prefix text;
  v_id     uuid;
begin
  if not private.has_org_role(p_org_id, 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if coalesce((private.org_limits(p_org_id) ->> 'api_access')::boolean, false) is not true then
    raise exception 'plan_feature_unavailable:api_access' using errcode = 'P0001';
  end if;
  if p_project_id is not null and not exists (
       select 1 from public.projects where projects.id = p_project_id and organization_id = p_org_id) then
    raise exception 'project not in organization' using errcode = '42501';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'expires_at must be in the future' using errcode = '22023';
  end if;

  v_key    := 'oseo_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_prefix := left(v_key, 13);

  insert into public.api_keys (organization_id, project_id, name, key_prefix, key_hash, scopes, expires_at, created_by)
  values (p_org_id, p_project_id, p_name, v_prefix,
          encode(extensions.digest(v_key, 'sha256'), 'hex'),
          coalesce(p_scopes, array['read']), p_expires_at, (select auth.uid()))
  returning api_keys.id into v_id;

  perform private.log_action(p_org_id, 'api_key.created', 'api_key', v_id::text,
    jsonb_build_object('scopes', p_scopes, 'project_id', p_project_id));

  return query select v_id, v_key, v_prefix;
end;
$$;

create or replace function public.revoke_api_key(p_key_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select organization_id into v_org from public.api_keys where id = p_key_id;
  if v_org is null or not private.has_org_role(v_org, 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update public.api_keys set revoked_at = coalesce(revoked_at, now()) where id = p_key_id;
  perform private.log_action(v_org, 'api_key.revoked', 'api_key', p_key_id::text);
end;
$$;

-- Queue a site audit (checks role, concurrency and monthly page quota).
create or replace function public.request_site_audit(p_project_id uuid, p_config jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org        uuid;
  v_audit_id   uuid;
  v_max_pages  bigint;
  v_quota      bigint;
  v_used       bigint;
  v_pages      integer;
begin
  select organization_id into v_org from public.projects where id = p_project_id and archived_at is null;
  if v_org is null or not private.has_org_role(v_org, 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  if exists (select 1 from public.site_audits
             where project_id = p_project_id and status in ('queued', 'crawling', 'analyzing')) then
    raise exception 'an audit is already running for this project' using errcode = 'P0001';
  end if;

  v_max_pages := coalesce(private.org_limit(v_org, 'max_pages_per_audit'), 100000);
  v_quota     := nullif(((private.org_limits(v_org) -> 'quota') ->> 'audit_page')::bigint, -1);
  select coalesce(sum(quantity), 0) into v_used
  from public.usage_records
  where organization_id = v_org and metric = 'audit_page'
    and occurred_at >= private.org_period_start(v_org);

  v_pages := least(coalesce((p_config ->> 'max_pages')::integer, 500), v_max_pages)::integer;
  if v_quota is not null then
    if v_used >= v_quota
       and coalesce((private.org_limits(v_org) ->> 'overage_enabled')::boolean, false) is not true then
      raise exception 'quota_exceeded:audit_page' using errcode = 'P0001';
    end if;
  end if;
  v_pages := greatest(v_pages, 1);

  insert into public.site_audits (project_id, config, pages_limit, triggered_by, trigger_source)
  values (p_project_id, coalesce(p_config, '{}'::jsonb) || jsonb_build_object('max_pages', v_pages),
          v_pages, (select auth.uid()), 'manual')
  returning id into v_audit_id;

  insert into public.jobs (queue, organization_id, project_id, payload, dedupe_key, priority)
  values ('site_audit', v_org, p_project_id, jsonb_build_object('audit_id', v_audit_id),
          'site_audit:' || p_project_id::text,
          case when (private.org_limits(v_org) ->> 'white_label')::boolean then 50 else 100 end);

  return v_audit_id;
end;
$$;

-- Quota overview for dashboards (any member).
create or replace function public.get_usage_summary(p_org_id uuid)
returns table (metric public.usage_metric, used bigint, quota bigint, period_start timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_start timestamptz;
  v_quota jsonb;
begin
  if not private.has_org_role(p_org_id, 'viewer') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  v_start := private.org_period_start(p_org_id);
  v_quota := coalesce(private.org_limits(p_org_id) -> 'quota', '{}'::jsonb);

  return query
  select m.metric,
         coalesce((select sum(u.quantity) from public.usage_records u
                   where u.organization_id = p_org_id and u.metric = m.metric
                     and u.occurred_at >= v_start), 0)::bigint,
         nullif((v_quota ->> m.metric::text)::bigint, -1),
         v_start
  from unnest(enum_range(null::public.usage_metric)) as m(metric);
end;
$$;

-- -----------------------------------------------------------------------------
-- 19. Service-role functions (API server, workers, Stripe webhook)
-- -----------------------------------------------------------------------------
-- Resolve an API key. Returns nothing for unknown / revoked / expired keys.
create or replace function public.verify_api_key(p_api_key text)
returns table (api_key_id uuid, organization_id uuid, project_id uuid, scopes text[], rate_limit_per_min integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.api_keys;
begin
  select * into v_row
  from public.api_keys k
  where k.key_hash = encode(extensions.digest(p_api_key, 'sha256'), 'hex')
    and k.revoked_at is null
    and (k.expires_at is null or k.expires_at > now());

  if v_row.id is null then
    return;
  end if;

  -- Throttled "last used" write (at most once per minute per key).
  update public.api_keys
     set last_used_at = now()
   where id = v_row.id
     and (last_used_at is null or last_used_at < now() - interval '1 minute');

  return query select v_row.id, v_row.organization_id, v_row.project_id, v_row.scopes, v_row.rate_limit_per_min;
end;
$$;

-- Atomically check quota and record usage. Idempotent on p_idempotency_key.
-- allowed = false → caller must not perform (or must roll back) the work.
create or replace function public.record_usage(
  p_org_id            uuid,
  p_metric            public.usage_metric,
  p_quantity          integer,
  p_idempotency_key   text,
  p_project_id        uuid default null,
  p_source            text default 'app',
  p_api_key_id        uuid default null,
  p_job_id            bigint default null,
  p_provider          text default null,
  p_provider_cost_usd numeric default null,
  p_enforce_quota     boolean default true,
  p_metadata          jsonb default '{}'::jsonb)
returns table (allowed boolean, used bigint, quota bigint, is_overage boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limits  jsonb := private.org_limits(p_org_id);
  v_quota   bigint := nullif(((v_limits -> 'quota') ->> p_metric::text)::bigint, -1);
  v_overage boolean := coalesce((v_limits ->> 'overage_enabled')::boolean, false);
  v_used    bigint;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'quantity must be positive' using errcode = '22023';
  end if;

  -- Replay of an already-recorded event → report success without double counting.
  if exists (select 1 from public.usage_records where idempotency_key = p_idempotency_key) then
    return query select true, null::bigint, v_quota, false;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_org_id::text || ':usage:' || p_metric::text, 0));

  select coalesce(sum(u.quantity), 0) into v_used
  from public.usage_records u
  where u.organization_id = p_org_id and u.metric = p_metric
    and u.occurred_at >= private.org_period_start(p_org_id);

  if p_enforce_quota and v_quota is not null and v_used + p_quantity > v_quota and not v_overage then
    return query select false, v_used, v_quota, false;
    return;
  end if;

  insert into public.usage_records (organization_id, project_id, metric, quantity, source, api_key_id,
                                    job_id, provider, provider_cost_usd, idempotency_key, metadata)
  values (p_org_id, p_project_id, p_metric, p_quantity, p_source, p_api_key_id,
          p_job_id, p_provider, p_provider_cost_usd, p_idempotency_key, coalesce(p_metadata, '{}'::jsonb))
  on conflict (idempotency_key) do nothing;

  return query select true, v_used + p_quantity, v_quota,
                      (v_quota is not null and v_used + p_quantity > v_quota);
end;
$$;

-- Claim up to p_limit jobs for a worker. Also recovers jobs whose worker died.
create or replace function public.claim_jobs(
  p_queues        text[],
  p_worker_id     text,
  p_limit         integer default 1,
  p_stale_after   interval default interval '10 minutes')
returns setof public.jobs
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Requeue stale running jobs (no heartbeat within p_stale_after).
  update public.jobs
     set status = case when attempts >= max_attempts then 'dead'::public.job_status else 'queued'::public.job_status end,
         locked_by = null, locked_at = null,
         last_error = coalesce(last_error, '') || ' [stale lock released]',
         finished_at = case when attempts >= max_attempts then now() end
   where status = 'running'
     and queue = any (p_queues)
     and coalesce(heartbeat_at, locked_at) < now() - p_stale_after;

  return query
  update public.jobs j
     set status = 'running', locked_by = p_worker_id, locked_at = now(), heartbeat_at = now(),
         attempts = j.attempts + 1
   where j.id in (
     select id from public.jobs
     where status = 'queued' and queue = any (p_queues) and run_after <= now()
     order by priority, run_after, id
     limit greatest(p_limit, 1)
     for update skip locked)
  returning j.*;
end;
$$;

create or replace function public.heartbeat_job(p_job_id bigint, p_worker_id text, p_progress numeric default null)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update public.jobs
     set heartbeat_at = now(), progress = coalesce(p_progress, progress)
   where id = p_job_id and locked_by = p_worker_id and status = 'running'
  returning true;
$$;

create or replace function public.complete_job(p_job_id bigint, p_worker_id text, p_result jsonb default null)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.jobs
     set status = 'succeeded', result = p_result, progress = 100, finished_at = now(), locked_by = null
   where id = p_job_id and locked_by = p_worker_id;
$$;

-- Exponential backoff: 30s, 2m, 8m, 32m, … capped at 6h.
create or replace function public.fail_job(p_job_id bigint, p_worker_id text, p_error text, p_retryable boolean default true)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.jobs
     set status = case when not p_retryable or attempts >= max_attempts
                       then 'dead'::public.job_status else 'queued'::public.job_status end,
         run_after = now() + least(interval '30 seconds' * power(4, greatest(attempts - 1, 0)), interval '6 hours'),
         last_error = left(p_error, 4000),
         locked_by = null, locked_at = null,
         finished_at = case when not p_retryable or attempts >= max_attempts then now() end
   where id = p_job_id and locked_by = p_worker_id;
$$;

-- Scheduler: batch due keywords into rank_check jobs (≤100 keywords / job).
create or replace function public.enqueue_due_rank_checks(p_batch_size integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_jobs integer;
begin
  with due as (
    select k.id, k.project_id, k.organization_id, k.frequency
    from public.keyword_tracking k
    join public.projects p on p.id = k.project_id and p.archived_at is null
    where k.is_active and k.next_check_at <= now()
    for update of k skip locked
  ),
  bumped as (
    update public.keyword_tracking k
       set next_check_at = date_trunc('day', now()) + case d.frequency
                              when 'daily'   then interval '1 day'
                              when 'weekly'  then interval '7 days'
                              when 'monthly' then interval '1 month' end
                           + make_interval(mins => (abs(hashtext(k.id::text)) % 360)) -- spread load over 6h
      from due d
     where k.id = d.id
    returning d.id, d.project_id, d.organization_id
  ),
  chunks as (
    select organization_id, project_id,
           (row_number() over (partition by project_id order by id) - 1) / greatest(p_batch_size, 1) as chunk,
           id
    from bumped
  ),
  inserted as (
    insert into public.jobs (queue, organization_id, project_id, payload, dedupe_key)
    select 'rank_check', organization_id, project_id,
           jsonb_build_object('keyword_ids', jsonb_agg(id), 'check_date', current_date),
           'rank_check:' || project_id::text || ':' || current_date::text || ':' || chunk::text
    from chunks
    group by organization_id, project_id, chunk
    on conflict do nothing
    returning 1
  )
  select count(*) into v_jobs from inserted;
  return v_jobs;
end;
$$;

-- Housekeeping: expired cache rows & very old finished jobs.
create or replace function private.run_maintenance()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.ensure_keyword_position_partitions(3);
  delete from private.provider_cache where expires_at < now();
  delete from public.jobs where status in ('succeeded', 'cancelled') and finished_at < now() - interval '30 days';
  delete from public.organization_invitations where accepted_at is null and expires_at < now() - interval '30 days';
end;
$$;

-- -----------------------------------------------------------------------------
-- 20. New-user bootstrap: personal workspace on sign-up
-- -----------------------------------------------------------------------------
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_base text := coalesce(nullif(split_part(new.email, '@', 1), ''), 'workspace');
  v_slug text;
begin
  v_slug := left(trim(both '-' from regexp_replace(lower(v_base), '[^a-z0-9]+', '-', 'g')), 30);
  if v_slug = '' then v_slug := 'workspace'; end if;
  v_slug := v_slug || '-' || substr(md5(new.id::text), 1, 6);

  insert into public.organizations (name, slug, is_personal, created_by, billing_email)
  values (coalesce(new.raw_user_meta_data ->> 'full_name', v_base) || ' workspace', v_slug, true, new.id, lower(new.email))
  returning id into v_org;

  insert into public.organization_members (organization_id, user_id, role)
  values (v_org, new.id, 'owner');
  return new;
end;
$$;

create trigger on_auth_user_created_openseo
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- -----------------------------------------------------------------------------
-- 21. Row Level Security
-- -----------------------------------------------------------------------------
alter table public.plans                    enable row level security;
alter table public.organizations            enable row level security;
alter table public.organization_members     enable row level security;
alter table public.organization_invitations enable row level security;
alter table public.subscriptions            enable row level security;
alter table public.projects                 enable row level security;
alter table public.keyword_tracking         enable row level security;
alter table public.keyword_positions        enable row level security;
alter table public.competitor_domains       enable row level security;
alter table public.competitor_keywords      enable row level security;
alter table public.audit_issue_types        enable row level security;
alter table public.site_audits              enable row level security;
alter table public.audit_pages              enable row level security;
alter table public.audit_issues             enable row level security;
alter table public.api_keys                 enable row level security;
alter table public.integrations             enable row level security;
alter table public.usage_records            enable row level security;
alter table public.jobs                     enable row level security;
alter table public.ai_analyses              enable row level security;
alter table public.reports                  enable row level security;
alter table public.audit_log                enable row level security;

-- Catalogues
create policy plans_read on public.plans
  for select to anon, authenticated using (is_public);
create policy audit_issue_types_read on public.audit_issue_types
  for select to authenticated using (true);

-- Organizations
create policy organizations_select on public.organizations
  for select to authenticated using (private.has_org_role(id, 'viewer'));
create policy organizations_update on public.organizations
  for update to authenticated
  using (private.has_org_role(id, 'admin')) with check (private.has_org_role(id, 'admin'));
create policy organizations_delete on public.organizations
  for delete to authenticated using (private.has_org_role(id, 'owner'));
-- INSERT only via public.create_organization().

-- Members
create policy members_select on public.organization_members
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy members_update on public.organization_members
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy members_delete on public.organization_members
  for delete to authenticated
  using (
    user_id = (select auth.uid())                                   -- leave org
    or (private.has_org_role(organization_id, 'admin') and role <> 'owner')
    or private.has_org_role(organization_id, 'owner'));
-- INSERT only via accept_invitation() / create_organization().

-- Invitations
create policy invitations_select on public.organization_invitations
  for select to authenticated using (private.has_org_role(organization_id, 'admin'));
create policy invitations_delete on public.organization_invitations
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

-- Subscriptions (written by Stripe webhook with service_role)
create policy subscriptions_select on public.subscriptions
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

-- Standard tenant data: viewers read, admins write.
create policy projects_select on public.projects
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy projects_insert on public.projects
  for insert to authenticated with check (private.has_org_role(organization_id, 'admin'));
create policy projects_update on public.projects
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy projects_delete on public.projects
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

-- Child tables: organization_id is trigger-derived from project_id, so the
-- WITH CHECK is evaluated against the real owner of the project.
create policy keyword_tracking_select on public.keyword_tracking
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy keyword_tracking_insert on public.keyword_tracking
  for insert to authenticated with check (private.has_org_role(organization_id, 'admin'));
create policy keyword_tracking_update on public.keyword_tracking
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy keyword_tracking_delete on public.keyword_tracking
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy keyword_positions_select on public.keyword_positions
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

create policy competitor_domains_select on public.competitor_domains
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy competitor_domains_insert on public.competitor_domains
  for insert to authenticated with check (private.has_org_role(organization_id, 'admin'));
create policy competitor_domains_update on public.competitor_domains
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy competitor_domains_delete on public.competitor_domains
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy competitor_keywords_select on public.competitor_keywords
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

create policy site_audits_select on public.site_audits
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy audit_pages_select on public.audit_pages
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy audit_issues_select on public.audit_issues
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

create policy api_keys_select on public.api_keys
  for select to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy integrations_select on public.integrations
  for select to authenticated using (private.has_org_role(organization_id, 'admin'));
create policy integrations_insert on public.integrations
  for insert to authenticated with check (
    private.has_org_role(organization_id, 'admin')
    and (project_id is null or exists (
      select 1 from public.projects p where p.id = project_id and p.organization_id = integrations.organization_id)));
create policy integrations_update on public.integrations
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy integrations_delete on public.integrations
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy usage_records_select on public.usage_records
  for select to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy jobs_select on public.jobs
  for select to authenticated using (organization_id is not null and private.has_org_role(organization_id, 'viewer'));

create policy ai_analyses_select on public.ai_analyses
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

create policy reports_select on public.reports
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));
create policy reports_insert on public.reports
  for insert to authenticated with check (private.has_org_role(organization_id, 'admin'));
create policy reports_update on public.reports
  for update to authenticated
  using (private.has_org_role(organization_id, 'admin'))
  with check (private.has_org_role(organization_id, 'admin'));
create policy reports_delete on public.reports
  for delete to authenticated using (private.has_org_role(organization_id, 'admin'));

create policy audit_log_select on public.audit_log
  for select to authenticated using (organization_id is not null and private.has_org_role(organization_id, 'admin'));

-- -----------------------------------------------------------------------------
-- 22. Grants (defence in depth on top of RLS)
-- -----------------------------------------------------------------------------
-- Supabase grants ALL on new public tables to anon/authenticated by default.
-- Reset to least privilege for every OpenSEO table.
do $$
declare
  t text;
begin
  foreach t in array array[
    'plans', 'organizations', 'organization_members', 'organization_invitations', 'subscriptions',
    'projects', 'keyword_tracking', 'keyword_positions', 'competitor_domains', 'competitor_keywords',
    'audit_issue_types', 'site_audits', 'audit_pages', 'audit_issues', 'api_keys', 'integrations',
    'usage_records', 'jobs', 'ai_analyses', 'reports', 'audit_log']
  loop
    execute format('revoke all on table public.%I from anon, authenticated', t);
    execute format('grant all on table public.%I to service_role', t);
  end loop;
end;
$$;

grant all on all tables in schema private to service_role;
grant all on all sequences in schema public to service_role;

-- Read access (rows still filtered by RLS)
grant select on public.plans to anon, authenticated;
grant select on public.audit_issue_types, public.subscriptions, public.keyword_positions,
                public.competitor_keywords, public.site_audits, public.audit_pages, public.audit_issues,
                public.usage_records, public.jobs, public.ai_analyses, public.audit_log,
                public.organization_members, public.organization_invitations
  to authenticated;

-- Organizations: everything readable, but billing/Stripe fields are server-owned.
grant select, delete on public.organizations to authenticated;
grant update (name, billing_email, country_code, vat_id, default_locale, brand_name, brand_logo_path,
              brand_primary_color, brand_accent_color, report_footer_text, settings)
  on public.organizations to authenticated;

grant update (role) on public.organization_members to authenticated;
grant delete on public.organization_members, public.organization_invitations to authenticated;

grant select, insert, update, delete on public.projects, public.keyword_tracking,
                                        public.competitor_domains, public.reports
  to authenticated;

-- api_keys: never expose key_hash to clients.
grant select (id, organization_id, project_id, name, key_prefix, scopes, rate_limit_per_min,
              last_used_at, expires_at, revoked_at, created_by, created_at)
  on public.api_keys to authenticated;

-- integrations: vault_secret_id / status are server-managed.
grant select (id, organization_id, project_id, provider, display_name, status, config,
              last_synced_at, last_error, created_by, created_at, updated_at)
  on public.integrations to authenticated;
grant insert (organization_id, project_id, provider, display_name, config)
  on public.integrations to authenticated;
grant update (display_name, config) on public.integrations to authenticated;
grant delete on public.integrations to authenticated;

-- Function execution
revoke all on function public.create_organization(text, text) from public, anon;
revoke all on function public.invite_member(uuid, text, public.org_role) from public, anon;
revoke all on function public.accept_invitation(text) from public, anon;
revoke all on function public.create_api_key(uuid, text, text[], uuid, timestamptz) from public, anon;
revoke all on function public.revoke_api_key(uuid) from public, anon;
revoke all on function public.request_site_audit(uuid, jsonb) from public, anon;
revoke all on function public.get_usage_summary(uuid) from public, anon;
grant execute on function public.create_organization(text, text) to authenticated;
grant execute on function public.invite_member(uuid, text, public.org_role) to authenticated;
grant execute on function public.accept_invitation(text) to authenticated;
grant execute on function public.create_api_key(uuid, text, text[], uuid, timestamptz) to authenticated;
grant execute on function public.revoke_api_key(uuid) to authenticated;
grant execute on function public.request_site_audit(uuid, jsonb) to authenticated;
grant execute on function public.get_usage_summary(uuid) to authenticated;

-- Service-only RPCs
revoke all on function public.verify_api_key(text) from public, anon, authenticated;
revoke all on function public.record_usage(uuid, public.usage_metric, integer, text, uuid, text, uuid, bigint, text, numeric, boolean, jsonb) from public, anon, authenticated;
revoke all on function public.claim_jobs(text[], text, integer, interval) from public, anon, authenticated;
revoke all on function public.heartbeat_job(bigint, text, numeric) from public, anon, authenticated;
revoke all on function public.complete_job(bigint, text, jsonb) from public, anon, authenticated;
revoke all on function public.fail_job(bigint, text, text, boolean) from public, anon, authenticated;
revoke all on function public.enqueue_due_rank_checks(integer) from public, anon, authenticated;
grant execute on function public.verify_api_key(text) to service_role;
grant execute on function public.record_usage(uuid, public.usage_metric, integer, text, uuid, text, uuid, bigint, text, numeric, boolean, jsonb) to service_role;
grant execute on function public.claim_jobs(text[], text, integer, interval) to service_role;
grant execute on function public.heartbeat_job(bigint, text, numeric) to service_role;
grant execute on function public.complete_job(bigint, text, jsonb) to service_role;
grant execute on function public.fail_job(bigint, text, text, boolean) to service_role;
grant execute on function public.enqueue_due_rank_checks(integer) to service_role;

-- Internal helpers are not callable by clients.
revoke all on function private.log_action(uuid, text, text, text, jsonb) from public;
revoke all on function private.run_maintenance() from public;
revoke all on function private.ensure_keyword_position_partitions(int) from public;
grant execute on function private.run_maintenance() to service_role;

-- -----------------------------------------------------------------------------
-- 23. Seed: plans & audit checks
-- -----------------------------------------------------------------------------
insert into public.plans (id, name, description, is_public, sort_order, price_monthly_cents, price_yearly_cents, limits) values
('free', 'Free', 'Side projects and evaluation', true, 0, 0, 0, '{
  "max_projects": 1, "max_keywords": 25, "max_seats": 1, "max_competitors_per_project": 2,
  "max_pages_per_audit": 250, "rank_check_min_frequency": "weekly", "rank_depth": 20,
  "api_access": false, "white_label": false, "custom_domain": false, "overage_enabled": false,
  "quota": {"serp_query": 300, "keyword_lookup": 50, "audit_page": 500, "backlink_query": 10,
            "ai_credit": 20, "api_call": 0, "report_render": 2}}'),
('pro', 'Pro', 'Freelancers and in-house marketers', true, 10, 4900, 49000, '{
  "max_projects": 5, "max_keywords": 500, "max_seats": 3, "max_competitors_per_project": 10,
  "max_pages_per_audit": 5000, "rank_check_min_frequency": "daily", "rank_depth": 20,
  "api_access": true, "white_label": false, "custom_domain": false, "overage_enabled": true,
  "quota": {"serp_query": 5000, "keyword_lookup": 3000, "audit_page": 25000, "backlink_query": 200,
            "ai_credit": 200, "api_call": 10000, "report_render": 30}}'),
('agency', 'Agency', 'Agencies: client projects and white-label reports', true, 20, 14900, 149000, '{
  "max_projects": 40, "max_keywords": 3000, "max_seats": 10, "max_competitors_per_project": 20,
  "max_pages_per_audit": 25000, "rank_check_min_frequency": "daily", "rank_depth": 50,
  "api_access": true, "white_label": true, "custom_domain": true, "overage_enabled": true,
  "quota": {"serp_query": 30000, "keyword_lookup": 15000, "audit_page": 200000, "backlink_query": 1500,
            "ai_credit": 1200, "api_call": 100000, "report_render": 300}}'),
('enterprise', 'Enterprise', 'Custom contract, SSO and SLA', false, 30, 0, 0, '{
  "max_projects": -1, "max_keywords": -1, "max_seats": -1, "max_competitors_per_project": -1,
  "max_pages_per_audit": 100000, "rank_check_min_frequency": "daily", "rank_depth": 100,
  "api_access": true, "white_label": true, "custom_domain": true, "overage_enabled": true,
  "quota": {"serp_query": -1, "keyword_lookup": -1, "audit_page": -1, "backlink_query": -1,
            "ai_credit": -1, "api_call": -1, "report_render": -1}}');

insert into public.audit_issue_types (code, category, severity, title, description, how_to_fix, weight) values
('http_5xx',              'crawlability', 'error',   'Server error (5xx)',            'Page returned a 5xx status code.',                         'Fix the server-side error or remove internal links to the URL.', 10),
('http_4xx',              'crawlability', 'error',   'Broken page (4xx)',             'Internally linked page returned a 4xx status code.',       'Restore the page, 301-redirect it, or update internal links.', 8),
('redirect_chain',        'crawlability', 'warning', 'Redirect chain',                'URL passes through 2+ redirects before resolving.',        'Link directly to the final destination URL.', 4),
('blocked_by_robots',     'crawlability', 'warning', 'Blocked by robots.txt',         'Internally linked URL is disallowed in robots.txt.',       'Allow crawling or remove the internal links.', 4),
('noindex_in_sitemap',    'crawlability', 'error',   'Noindex URL in sitemap',        'Sitemap lists a URL marked noindex.',                      'Remove noindex URLs from the XML sitemap.', 6),
('orphan_page',           'links',        'notice',  'Orphan page',                   'Page in sitemap has no internal links pointing to it.',    'Link to the page from relevant content.', 2),
('broken_internal_link',  'links',        'error',   'Broken internal link',          'Internal link points to a 4xx/5xx URL.',                   'Update or remove the link.', 7),
('missing_title',         'on_page',      'error',   'Missing <title>',               'Page has no title tag.',                                   'Add a unique, descriptive title (≈50–60 chars).', 8),
('duplicate_title',       'on_page',      'warning', 'Duplicate title',               'Several pages share the same title.',                      'Write a unique title per page.', 5),
('title_too_long',        'on_page',      'notice',  'Title too long',                'Title likely truncated in SERP.',                          'Shorten to ≈60 characters.', 1),
('missing_meta_description','on_page',    'warning', 'Missing meta description',      'Page has no meta description.',                            'Add a compelling 120–155 character description.', 3),
('missing_h1',            'on_page',      'warning', 'Missing H1',                    'Page has no H1 heading.',                                  'Add one H1 describing the page topic.', 3),
('thin_content',          'on_page',      'warning', 'Thin content',                  'Indexable page with very low word count.',                 'Expand content or consolidate / noindex the page.', 4),
('duplicate_content',     'on_page',      'warning', 'Duplicate content',             'Page body is identical to another URL.',                   'Canonicalise or consolidate duplicates.', 5),
('missing_canonical',     'on_page',      'notice',  'Missing canonical',             'Indexable page without rel=canonical.',                    'Add a self-referencing canonical.', 1),
('image_missing_alt',     'on_page',      'notice',  'Images without alt text',       'One or more images lack alt attributes.',                  'Add descriptive alt text.', 1),
('slow_response',         'performance',  'warning', 'Slow server response',          'TTFB above threshold.',                                    'Improve caching / hosting / backend performance.', 4),
('poor_lcp',              'performance',  'warning', 'Poor LCP',                      'Largest Contentful Paint > 2.5 s.',                        'Optimise hero media, fonts and render-blocking resources.', 4),
('poor_cls',              'performance',  'warning', 'Poor CLS',                      'Cumulative Layout Shift > 0.1.',                           'Reserve space for media/ads; avoid late-injected content.', 3),
('mixed_content',         'performance',  'error',   'Mixed content',                 'HTTPS page loads HTTP resources.',                         'Serve all resources over HTTPS.', 6),
('hreflang_invalid',      'international','warning', 'Invalid hreflang',              'hreflang missing return link or invalid code.',            'Fix language codes and reciprocal annotations.', 3),
('missing_structured_data','ai_readiness','notice',  'No structured data',            'No schema.org markup found.',                              'Add relevant JSON-LD (Organization, Product, Article, FAQ…).', 2),
('ai_crawler_blocked',    'ai_readiness', 'notice',  'AI crawlers blocked',           'robots.txt blocks GPTBot / ClaudeBot / PerplexityBot etc.', 'Decide intentionally; allow if AI-search visibility is a goal.', 1),
('js_only_content',       'ai_readiness', 'warning', 'Content requires JavaScript',   'Main content absent from raw HTML (rendered only via JS).','Server-render key content so non-JS crawlers and AI agents can read it.', 4),
('missing_llms_txt',      'ai_readiness', 'notice',  'No llms.txt',                   'Site does not publish /llms.txt.',                          'Optional: publish llms.txt summarising key content for LLM agents.', 0);

-- -----------------------------------------------------------------------------
-- 24. Storage buckets & policies (only when running on Supabase)
-- -----------------------------------------------------------------------------
-- Object paths are "<organization_id>/..." so the first folder scopes access.
do $$
begin
  if to_regclass('storage.buckets') is not null then
    -- Missing policies = no client access (deny by default), so a privilege
    -- error here is surfaced as a warning rather than aborting the migration.
    insert into storage.buckets (id, name, public)
    values ('reports', 'reports', false), ('branding', 'branding', false)
    on conflict (id) do nothing;

    execute $p$
      create policy openseo_reports_read on storage.objects for select to authenticated
      using (bucket_id = 'reports'
             and private.has_org_role(private.try_uuid((storage.foldername(name))[1]), 'viewer'))
    $p$;
    execute $p$
      create policy openseo_branding_read on storage.objects for select to authenticated
      using (bucket_id = 'branding'
             and private.has_org_role(private.try_uuid((storage.foldername(name))[1]), 'viewer'))
    $p$;
    execute $p$
      create policy openseo_branding_write on storage.objects for insert to authenticated
      with check (bucket_id = 'branding'
                  and private.has_org_role(private.try_uuid((storage.foldername(name))[1]), 'admin'))
    $p$;
    execute $p$
      create policy openseo_branding_update on storage.objects for update to authenticated
      using (bucket_id = 'branding'
             and private.has_org_role(private.try_uuid((storage.foldername(name))[1]), 'admin'))
    $p$;
    execute $p$
      create policy openseo_branding_delete on storage.objects for delete to authenticated
      using (bucket_id = 'branding'
             and private.has_org_role(private.try_uuid((storage.foldername(name))[1]), 'admin'))
    $p$;
  end if;
exception when insufficient_privilege then
  raise warning 'OpenSEO storage policies not created (%). Create them from the dashboard.', sqlerrm;
end;
$$;
