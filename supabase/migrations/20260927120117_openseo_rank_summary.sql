-- =============================================================================
-- OpenSEO — rank summary helpers (migration 0004)
-- Daily project-level ranking aggregates for dashboards and reports.
-- SECURITY INVOKER: callers only see rows RLS allows them to see.
-- =============================================================================

-- Estimated organic click-through rate by position (industry-average curve).
-- Used for the visibility index and traffic estimates; keep in sync with
-- apps/web/src/lib/seo-metrics.ts.
create or replace function public.ctr_for_position(p_position integer)
returns numeric
language sql
immutable
parallel safe
set search_path = ''
as $$
  select case
    when p_position is null or p_position < 1 then 0
    when p_position = 1 then 0.28
    when p_position = 2 then 0.15
    when p_position = 3 then 0.11
    when p_position = 4 then 0.08
    when p_position = 5 then 0.06
    when p_position = 6 then 0.05
    when p_position = 7 then 0.04
    when p_position = 8 then 0.03
    when p_position = 9 then 0.025
    when p_position = 10 then 0.02
    when p_position <= 20 then 0.01
    else 0
  end::numeric;
$$;

-- One row per check date in the window: how the project's tracked keywords ranked.
create or replace function public.project_rank_summary(p_project_id uuid, p_days integer default 30)
returns table (
  check_date      date,
  checked         integer,
  ranked          integer,
  avg_position    numeric,
  top3            integer,
  top10           integer,
  visibility      numeric,
  est_traffic     numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select p.check_date,
         count(*)::integer                                        as checked,
         count(p.position)::integer                               as ranked,
         round(avg(p.position), 1)                                as avg_position,
         count(*) filter (where p.position <= 3)::integer         as top3,
         count(*) filter (where p.position <= 10)::integer        as top10,
         round(100 * sum(public.ctr_for_position(p.position))
               / nullif(count(*) * public.ctr_for_position(1), 0), 1) as visibility,
         round(sum(public.ctr_for_position(p.position) * coalesce(k.search_volume, 0)), 0) as est_traffic
  from public.keyword_positions p
  join public.keyword_tracking k on k.id = p.keyword_id
  where p.project_id = p_project_id
    and p.check_date >= current_date - greatest(p_days, 1)
  group by p.check_date
  order by p.check_date;
$$;

revoke all on function public.project_rank_summary(uuid, integer) from public, anon;
grant execute on function public.project_rank_summary(uuid, integer) to authenticated, service_role;
grant execute on function public.ctr_for_position(integer) to authenticated, service_role;
