-- Tenant-isolation & business-rule tests for the OpenSEO core schema.
-- Run with tests/db/run.sh (plain PostgreSQL + supabase_stub.sql).
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- Identities -----------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');

create or replace function pg_temp.as_user(p_uid text, p_email text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'email', p_email, 'role', 'authenticated')::text, false);
  execute 'set role authenticated';
end $$;

create or replace function pg_temp.as_service() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', false);
  execute 'set role service_role';
end $$;

create or replace function pg_temp.expect_error(p_sql text, p_like text) returns void
language plpgsql as $$
begin
  execute p_sql;
  raise exception 'EXPECTED ERROR (%) but statement succeeded: %', p_like, p_sql;
exception when others then
  if sqlerrm like 'EXPECTED ERROR%' then raise; end if;
  if sqlerrm not ilike '%' || p_like || '%' then
    raise exception 'wrong error for %: got "%" expected like "%"', p_sql, sqlerrm, p_like;
  end if;
end $$;

-- 1. Sign-up creates a personal workspace --------------------------------------
do $$
begin
  assert (select count(*) from public.organizations where is_personal) = 2, 'personal orgs';
  assert (select count(*) from public.organization_members where role = 'owner') = 2, 'owners';
end $$;
\echo ok 1 personal workspace on sign-up

-- 2. Alice creates an agency org, gets Agency plan -----------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select public.create_organization('Agency Oy', 'agency-oy') as agency_id \gset
select set_config('t.agency_id', :'agency_id', false) \g /dev/null
reset role;
insert into public.subscriptions (organization_id, plan_id, status, current_period_start, current_period_end)
values (:'agency_id', 'agency', 'active', now() - interval '1 day', now() + interval '29 days');
\echo ok 2 create_organization

-- 3. Alice (owner) creates project + keywords ----------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
insert into public.projects (organization_id, name, domain, root_url, is_client_project, client_name)
values (:'agency_id', 'Asiakas 1', 'asiakas1.fi', 'https://asiakas1.fi/', true, 'Asiakas 1 Oy')
returning id as project_id \gset
select set_config('t.project_id', :'project_id', false) \g /dev/null
insert into public.keyword_tracking (project_id, organization_id, keyword)
values (:'project_id', '00000000-0000-0000-0000-000000000000', '  Sähköauton   Akku ')   -- bogus org id is overwritten
returning id as kw_id, organization_id as kw_org, location_code as kw_loc \gset
select set_config('t.kw_id', :'kw_id', false) \g /dev/null
select set_config('t.kw_org', :'kw_org', false) \g /dev/null
select set_config('t.kw_loc', :'kw_loc', false) \g /dev/null
select pg_temp.expect_error(format($q$insert into public.projects (organization_id, name, domain, root_url) values (%L, 'x', 'Bad.FI/path', 'x')$q$, :'agency_id'), 'check constraint');
select (select keyword_normalized from public.keyword_tracking where id = :'kw_id') = 'sähköauton akku' as ok_norm \gset
select set_config('t.ok_norm', :'ok_norm', false) \g /dev/null
reset role;
do $$ begin assert current_setting('t.ok_norm')::boolean, 'keyword normalisation'; end $$;
do $$ begin assert current_setting('t.kw_org')::uuid = current_setting('t.agency_id')::uuid, 'org derived from project'; assert current_setting('t.kw_loc')::int = 2840, 'default location'; end $$;
\echo ok 3 project + keyword, org_id derived by trigger

-- 4. Bob cannot see or write Alice's data --------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
do $$ begin
  assert (select count(*) from public.projects) = 0, 'bob sees no foreign projects';
  assert (select count(*) from public.keyword_tracking) = 0, 'bob sees no foreign keywords';
  assert (select count(*) from public.organizations) = 1, 'bob sees only his workspace';
end $$;
select pg_temp.expect_error(format(
  $q$insert into public.keyword_tracking (project_id, organization_id, keyword) values (%L, (select id from public.organizations limit 1), 'hack')$q$,
  :'project_id'), 'row-level security');
select pg_temp.expect_error(format(
  $q$insert into public.projects (organization_id, name, domain, root_url) values (%L, 'x', 'x.fi', 'https://x.fi')$q$,
  :'agency_id'), 'row-level security');
do $$ begin
  update public.projects set name = 'pwned';
  assert not found, 'bob cannot update foreign project';
end $$;
reset role;
\echo ok 4 cross-tenant read/write blocked

-- 5. Free plan hard caps ------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
select id as bob_org from public.organizations limit 1 \gset
select set_config('t.bob_org', :'bob_org', false) \g /dev/null
insert into public.projects (organization_id, name, domain, root_url) values (:'bob_org', 'Oma', 'oma.fi', 'https://oma.fi');
select pg_temp.expect_error(format(
  $q$insert into public.projects (organization_id, name, domain, root_url) values (%L, 'Toinen', 'toinen.fi', 'https://toinen.fi')$q$,
  :'bob_org'), 'plan_limit_exceeded:max_projects');
select pg_temp.expect_error(format($q$select public.create_api_key(%L, 'k')$q$, :'bob_org'), 'plan_feature_unavailable:api_access');
reset role;
\echo ok 5 plan limits + domain normalisation enforced

-- 6. API keys ------------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select api_key, id as api_key_id from public.create_api_key(:'agency_id', 'Looker', array['read','reports:read'], :'project_id') \gset
select set_config('t.api_key', :'api_key', false) \g /dev/null
select set_config('t.api_key_id', :'api_key_id', false) \g /dev/null
select pg_temp.expect_error('select key_hash from public.api_keys', 'permission denied');
do $$ begin assert (select count(*) from public.api_keys) = 1; end $$;
select pg_temp.expect_error(format($q$select * from public.verify_api_key(%L)$q$, :'api_key'), 'permission denied');
select pg_temp.expect_error(format($q$select public.create_api_key(%L, 'bad', array['admin'])$q$, :'agency_id'), 'check constraint');
reset role;
select pg_temp.as_service();
select organization_id as verified_org, project_id as verified_project from public.verify_api_key(:'api_key') \gset
select set_config('t.verified_org', :'verified_org', false) \g /dev/null
select set_config('t.verified_project', :'verified_project', false) \g /dev/null
do $$ begin
  assert (select count(*) from public.verify_api_key('oseo_wrong')) = 0, 'unknown key rejected';
end $$;
reset role;
do $$ begin assert current_setting('t.verified_org')::uuid = current_setting('t.agency_id')::uuid and current_setting('t.verified_project')::uuid = current_setting('t.project_id')::uuid, 'verify_api_key'; end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select public.revoke_api_key(:'api_key_id');
reset role;
select pg_temp.as_service();
do $$ begin assert (select count(*) from public.verify_api_key(current_setting('t.api_key'))) = 0, 'revoked key rejected'; end $$;
reset role;
\echo ok 6 api keys: hashed, scoped, revocable, service-only verification

-- 7. Positions (worker) + snapshot + isolation ---------------------------------
select pg_temp.as_service();
insert into public.keyword_positions (keyword_id, check_date, position, url, provider, organization_id, project_id)
values (:'kw_id', current_date - 1, 8, 'https://asiakas1.fi/a', 'dataforseo', gen_random_uuid(), gen_random_uuid()),
       (:'kw_id', current_date,     5, 'https://asiakas1.fi/a', 'dataforseo', gen_random_uuid(), gen_random_uuid());
reset role;
do $$
declare r record;
begin
  select current_position, previous_position, best_position into r from public.keyword_tracking where id = current_setting('t.kw_id')::uuid;
  assert r.current_position = 5 and r.previous_position = 8 and r.best_position = 5, 'snapshot ' || r::text;
  assert (select count(distinct organization_id) from public.keyword_positions) = 1, 'scope overwritten';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
do $$ begin assert (select count(*) from public.keyword_positions) = 2, 'alice sees positions'; end $$;
select pg_temp.expect_error('insert into public.keyword_positions (keyword_id, check_date, provider) values (gen_random_uuid(), current_date, $$x$$)', 'permission denied');
select pg_temp.expect_error(format('select * from private.keyword_positions_%s', to_char(now(), 'YYYY_MM')), 'permission denied');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
do $$ begin assert (select count(*) from public.keyword_positions) = 0, 'bob sees no positions'; end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
do $$
declare r record;
begin
  assert (select count(*) from public.project_rank_summary(current_setting('t.project_id')::uuid, 30)) = 2, 'two summary days';
  select * into r from public.project_rank_summary(current_setting('t.project_id')::uuid, 30) order by check_date desc limit 1;
  assert r.checked = 1 and r.ranked = 1 and r.avg_position = 5 and r.top10 = 1 and r.top3 = 0, 'summary ' || r::text;
  assert r.visibility = round(100 * 0.06 / 0.28, 1), 'visibility ' || r.visibility;
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
do $$ begin
  assert (select count(*) from public.project_rank_summary(current_setting('t.project_id')::uuid, 30)) = 0, 'bob gets no foreign summary';
end $$;
reset role;
\echo ok 7 positions partitioned, snapshot trigger, private partitions not readable, rank summary respects RLS

-- 8. Invitations & roles ------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select public.invite_member(:'agency_id', 'Bob@Client.fi', 'viewer') as invite_token \gset
select set_config('t.invite_token', :'invite_token', false) \g /dev/null
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
select public.accept_invitation(:'invite_token');
do $$ begin
  assert (select count(*) from public.projects where organization_id = current_setting('t.agency_id')::uuid) = 1, 'viewer reads projects';
  update public.organization_members set role = 'owner' where user_id = auth.uid() and organization_id = current_setting('t.agency_id')::uuid;
  assert not found, 'viewer cannot escalate';
  update public.projects set name = 'x' where organization_id = current_setting('t.agency_id')::uuid;
  assert not found, 'viewer cannot write';
end $$;
select pg_temp.expect_error(format($q$select public.accept_invitation(%L)$q$, :'invite_token'), 'invalid or expired');
reset role;
-- Promote Bob to admin: admin must not be able to grant owner.
update public.organization_members set role = 'admin'
 where organization_id = :'agency_id' and user_id = '00000000-0000-0000-0000-00000000000b';
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
select pg_temp.expect_error(format(
  $q$update public.organization_members set role = 'owner' where organization_id = %L and user_id = auth.uid()$q$,
  :'agency_id'), 'only owners');
do $$ begin
  delete from public.organization_members where role = 'owner' and organization_id = current_setting('t.agency_id')::uuid;
  assert not found, 'admin cannot remove owner';
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select pg_temp.expect_error(format(
  $q$delete from public.organization_members where organization_id = %L and user_id = auth.uid()$q$,
  :'agency_id'), 'at least one owner');
reset role;
\echo ok 8 invitations, role escalation blocked, last owner protected

-- 9. Usage metering & quotas --------------------------------------------------
select pg_temp.as_service();
do $$
declare r record;
begin
  select * into r from public.record_usage(current_setting('t.bob_org')::uuid, 'serp_query', 300, 'k1');
  assert r.allowed and r.used = 300, 'within quota';
  select * into r from public.record_usage(current_setting('t.bob_org')::uuid, 'serp_query', 1, 'k2');
  assert not r.allowed, 'free plan blocks overage';
  select * into r from public.record_usage(current_setting('t.bob_org')::uuid, 'serp_query', 300, 'k1');
  assert r.allowed, 'idempotent replay';
  assert (select sum(quantity) from public.usage_records where organization_id = current_setting('t.bob_org')::uuid) = 300, 'no double count';
  select * into r from public.record_usage(current_setting('t.agency_id')::uuid, 'serp_query', 50000, 'k3');
  assert r.allowed and r.is_overage, 'agency overage allowed & flagged';
end $$;
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
select pg_temp.expect_error(format($q$select * from public.record_usage(%L, 'serp_query', 1, 'x')$q$, :'bob_org'), 'permission denied');
do $$ begin
  assert (select used from public.get_usage_summary(current_setting('t.bob_org')::uuid) where metric = 'serp_query') = 300, 'summary';
end $$;
reset role;
\echo ok 9 usage metering: quota, idempotency, overage, service-only

-- 10. Job queue ----------------------------------------------------------------
select pg_temp.as_service();
do $$
declare n int; j public.jobs;
begin
  n := public.enqueue_due_rank_checks(100);
  assert n = 1, 'one rank job, got ' || n;
  assert public.enqueue_due_rank_checks(100) = 0, 'keyword not due twice';
  select * into j from public.claim_jobs(array['rank_check'], 'w1', 5);
  assert j.status = 'running' and j.attempts = 1, 'claimed';
  assert (select count(*) from public.claim_jobs(array['rank_check'], 'w2', 5)) = 0, 'skip locked';
  perform public.fail_job(j.id, 'w1', 'provider timeout');
  assert (select status from public.jobs where id = j.id) = 'queued', 'retry scheduled';
  assert (select run_after > now() from public.jobs where id = j.id), 'backoff';
end $$;
reset role;
\echo ok 10 job queue: enqueue, skip-locked claim, backoff

-- 11. Site audit request -------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
select public.request_site_audit(:'project_id', '{"max_pages": 999999}') as audit_id \gset
select set_config('t.audit_id', :'audit_id', false) \g /dev/null
select pg_temp.expect_error(format($q$select public.request_site_audit(%L)$q$, :'project_id'), 'already running');
do $$ begin
  assert (select pages_limit from public.site_audits where id = current_setting('t.audit_id')::uuid) = 25000, 'clamped to plan';
  assert (select count(*) from public.jobs where queue = 'site_audit') = 1, 'job visible to member';
end $$;
reset role;
select pg_temp.as_service();
insert into public.audit_pages (audit_id, organization_id, url, status_code) values (:'audit_id', gen_random_uuid(), 'https://asiakas1.fi/', 200)
returning id as page_id \gset
select set_config('t.page_id', :'page_id', false) \g /dev/null
insert into public.audit_issues (audit_id, organization_id, page_id, issue_code, severity, url)
values (:'audit_id', gen_random_uuid(), :'page_id', 'missing_title', 'error', 'https://asiakas1.fi/');
reset role;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
-- Bob is admin in agency now → sees issues; verify org scoping instead via his personal org.
do $$ begin
  assert (select count(*) from public.audit_issues where organization_id = current_setting('t.agency_id')::uuid) = 1, 'org derived for issue';
end $$;
reset role;
\echo ok 11 site audit request, clamp, dedupe

-- 11b. "Check now": on-demand rank check -----------------------------------------
do $$ begin
  assert (select last_provider from public.keyword_tracking where id = current_setting('t.kw_id')::uuid) = 'dataforseo',
    'snapshot keeps last provider';
end $$;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
do $$
declare j public.jobs;
begin
  assert public.request_rank_check(current_setting('t.project_id')::uuid) = 1, 'one keyword queued';
  select * into j from public.jobs where queue = 'rank_check' and (payload ->> 'manual')::boolean;
  assert j.priority = 10 and j.payload -> 'keyword_ids' = jsonb_build_array(current_setting('t.kw_id')), 'manual job ' || j::text;
  assert j.payload ->> 'requested_by' = '00000000-0000-0000-0000-00000000000a', 'requester recorded';
end $$;
select pg_temp.expect_error(format($q$select public.request_rank_check(%L)$q$, :'project_id'), 'rank_check_cooldown');
select pg_temp.expect_error(format($q$select public.request_rank_check((select id from public.projects where organization_id = %L))$q$, :'bob_org'), 'forbidden');
reset role;
-- A finished check older than an hour no longer blocks.
update public.jobs set status = 'succeeded', finished_at = now() - interval '2 hours'
 where queue = 'rank_check' and (payload ->> 'manual')::boolean;
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
do $$ begin assert public.request_rank_check(current_setting('t.project_id')::uuid) = 1, 'allowed after cooldown'; end $$;
reset role;
-- Bob's free workspace: no keywords, then quota exhausted (300/300 used in test 9).
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b', 'bob@client.fi');
select id as bob_project from public.projects where organization_id = :'bob_org' \gset
select pg_temp.expect_error(format($q$select public.request_rank_check(%L)$q$, :'bob_project'), 'no_keywords');
insert into public.keyword_tracking (project_id, organization_id, keyword) values (:'bob_project', :'bob_org', 'oma avainsana');
select pg_temp.expect_error(format($q$select public.request_rank_check(%L)$q$, :'bob_project'), 'quota_exceeded:serp_query');
reset role;
set role anon;
select pg_temp.expect_error(format($q$select public.request_rank_check(%L)$q$, :'project_id'), 'permission denied');
reset role;
\echo ok 11b check now: role, cooldown, quota, snapshot provider

-- 12. anon ---------------------------------------------------------------------
set role anon;
do $$ begin
  assert (select count(*) from public.plans) = 3, 'anon sees public plans only';
end $$;
select pg_temp.expect_error('select * from public.organizations', 'permission denied');
select pg_temp.expect_error($q$select public.create_organization('x')$q$, 'permission denied');
reset role;
\echo ok 12 anon limited to public plan catalogue

-- 13. Org deletion cascades cleanly --------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a', 'alice@agency.fi');
delete from public.organizations where id = :'agency_id';
reset role;
do $$ begin
  assert (select count(*) from public.projects where organization_id = current_setting('t.agency_id')::uuid) = 0, 'projects gone';
  assert (select count(*) from public.keyword_positions where organization_id = current_setting('t.agency_id')::uuid) = 0, 'positions gone';
end $$;
\echo ok 13 owner can delete organization (cascade)

\echo ALL TESTS PASSED
