-- Schema fingerprint: compare a deployed database with the local test build.
select 'functions' as part, md5(string_agg(pg_get_functiondef(p.oid), E'\n' order by n.nspname, p.proname, pg_get_function_identity_arguments(p.oid))) as md5, count(*)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private') and p.prokind = 'f'
union all
select 'policies', md5(string_agg(tablename || policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, ''), E'\n' order by tablename, policyname)), count(*)
from pg_policies where schemaname = 'public'
union all
select 'columns', md5(string_agg(table_schema || '.' || table_name || '.' || column_name || ':' || data_type || ':' || coalesce(column_default, '') || ':' || is_nullable, E'\n' order by table_schema, table_name, ordinal_position)), count(*)
from information_schema.columns where table_schema in ('public', 'private') and table_name not like 'keyword_positions_2%'
union all
select 'triggers', md5(string_agg(c.relname || t.tgname || pg_get_triggerdef(t.oid), E'\n' order by c.relname, t.tgname)), count(*)
from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal and n.nspname = 'public'
union all
select 'table_grants', md5(string_agg(table_name || grantee || privilege_type, E'\n' order by table_name, grantee, privilege_type)), count(*)
from information_schema.role_table_grants where table_schema = 'public' and grantee in ('anon', 'authenticated')
union all
select 'column_grants', md5(string_agg(table_name || column_name || grantee || privilege_type, E'\n' order by table_name, column_name, grantee, privilege_type)), count(*)
from information_schema.column_privileges where table_schema = 'public' and grantee in ('anon', 'authenticated')
  and (table_name, privilege_type) not in (select table_name, privilege_type from information_schema.role_table_grants where table_schema='public' and grantee = column_privileges.grantee)
union all
select 'seed', md5((select string_agg(id || limits::text, ',' order by id) from public.plans) || (select string_agg(code || weight, ',' order by code) from public.audit_issue_types)), 0
order by part;
