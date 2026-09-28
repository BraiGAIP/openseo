-- =============================================================================
-- OpenSEO — SERP change tracking and keyword difficulty (migration 0006)
--   * keyword_positions.top_domains: the organic top-10 domains of each check,
--     so competitor movements can be compared between checks.
--   * keyword_events: what changed for a keyword since its previous check
--     (position jumps, top-3/top-10 crossings, SERP features, AI Overview
--     citation, ranking URL, competitors). Written by the rank_check worker;
--     rules are documented in docs/ARCHITECTURE.md §8.6.
--   * keyword difficulty flows private.keyword_metrics → keyword_tracking
--     (column already existed; the worker now fills it from DataForSEO Labs).
-- =============================================================================

alter table public.keyword_positions add column if not exists top_domains text[];

create type public.keyword_event_kind as enum (
  'started_ranking', 'stopped_ranking',
  'entered_top3', 'left_top3', 'entered_top10', 'left_top10',
  'position_up', 'position_down',
  'url_changed',
  'feature_gained', 'feature_lost',
  'ai_overview_cited', 'ai_overview_uncited',
  'competitor_entered', 'competitor_left'
);

create table public.keyword_events (
  id               bigint generated always as identity primary key,
  keyword_id       uuid not null references public.keyword_tracking (id) on delete cascade,
  organization_id  uuid not null,
  project_id       uuid not null,
  check_date       date not null,
  kind             public.keyword_event_kind not null,
  subject          text not null default '',      -- feature name, competitor domain or new URL
  payload          jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now(),
  foreign key (project_id, organization_id)
    references public.projects (id, organization_id) on delete cascade,
  unique (keyword_id, check_date, kind, subject)
);

create index keyword_events_project_idx on public.keyword_events (project_id, check_date desc, id desc);
create index keyword_events_org_idx on public.keyword_events (organization_id);

-- organization_id / project_id always come from the keyword, never from the writer.
create trigger a_keyword_events_scope before insert on public.keyword_events
  for each row execute function private.set_scope_from_keyword();

alter table public.keyword_events enable row level security;

create policy keyword_events_select on public.keyword_events
  for select to authenticated using (private.has_org_role(organization_id, 'viewer'));

-- Supabase's default privileges grant everything on new tables to anon/authenticated.
revoke all on table public.keyword_events from public, anon, authenticated;
grant select on public.keyword_events to authenticated;
grant all on table public.keyword_events to service_role;
