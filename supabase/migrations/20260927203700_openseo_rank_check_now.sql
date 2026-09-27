-- =============================================================================
-- OpenSEO — on-demand rank checks and provider snapshot (migration 0005)
--   * keyword_tracking.last_provider: which provider produced the latest position,
--     so the UI can flag demo data ('mock') and fallback data ('serper').
--   * request_rank_check(): "Check now" button. Queues a high-priority rank_check
--     for every active keyword of a project, after role, cooldown and quota checks.
-- =============================================================================

alter table public.keyword_tracking add column if not exists last_provider text;

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
         last_check_date   = new.check_date,
         last_provider     = new.provider
   where k.id = new.keyword_id
     and (k.last_check_date is null or new.check_date >= k.last_check_date);
  return null;
end;
$$;

update public.keyword_tracking k
   set last_provider = p.provider
  from public.keyword_positions p
 where p.keyword_id = k.id and p.check_date = k.last_check_date and k.last_provider is null;

-- Queue an immediate rank check for all active keywords of a project.
-- Returns the number of keywords queued. Errors (P0001):
--   rank_check_cooldown        a manual check is running or finished within the last hour
--   no_keywords                nothing to check
--   quota_exceeded:serp_query  the check would exceed the monthly SERP quota (no overage)
create or replace function public.request_rank_check(p_project_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid;
  v_ids     uuid[];
  v_limits  jsonb;
  v_quota   bigint;
  v_used    bigint;
begin
  select organization_id into v_org from public.projects where id = p_project_id and archived_at is null;
  if v_org is null or not private.has_org_role(v_org, 'admin') then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  -- One manual check per project per hour; serialise concurrent clicks.
  perform pg_advisory_xact_lock(hashtextextended('rank_check:manual:' || p_project_id::text, 0));
  if exists (select 1 from public.jobs
             where project_id = p_project_id and queue = 'rank_check'
               and coalesce((payload ->> 'manual')::boolean, false)
               and (status in ('queued', 'running')
                    or (status = 'succeeded' and finished_at > now() - interval '1 hour'))) then
    raise exception 'rank_check_cooldown' using errcode = 'P0001';
  end if;

  select array_agg(id order by created_at) into v_ids
  from public.keyword_tracking
  where project_id = p_project_id and is_active;
  if v_ids is null then
    raise exception 'no_keywords' using errcode = 'P0001';
  end if;

  -- Every keyword costs at least one SERP page; the worker meters the exact amount.
  v_limits := private.org_limits(v_org);
  v_quota  := nullif(((v_limits -> 'quota') ->> 'serp_query')::bigint, -1);
  if v_quota is not null and coalesce((v_limits ->> 'overage_enabled')::boolean, false) is not true then
    select coalesce(sum(quantity), 0) into v_used
    from public.usage_records
    where organization_id = v_org and metric = 'serp_query'
      and occurred_at >= private.org_period_start(v_org);
    if v_used + cardinality(v_ids) > v_quota then
      raise exception 'quota_exceeded:serp_query' using errcode = 'P0001';
    end if;
  end if;

  insert into public.jobs (queue, organization_id, project_id, payload, dedupe_key, priority)
  select 'rank_check', v_org, p_project_id,
         jsonb_build_object('keyword_ids', jsonb_agg(c.id order by c.n), 'check_date', current_date,
                            'manual', true, 'requested_by', (select auth.uid())),
         'rank_check:manual:' || p_project_id::text || ':' || c.chunk::text,
         10
  from (select id, n, (n - 1) / 100 as chunk from unnest(v_ids) with ordinality as u(id, n)) c
  group by c.chunk
  on conflict do nothing;

  perform private.log_action(v_org, 'rank_check.requested', 'project', p_project_id::text,
                             jsonb_build_object('keywords', cardinality(v_ids)));
  return cardinality(v_ids);
end;
$$;

revoke all on function public.request_rank_check(uuid) from public, anon;
grant execute on function public.request_rank_check(uuid) to authenticated;
