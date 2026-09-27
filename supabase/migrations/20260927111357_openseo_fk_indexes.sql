-- =============================================================================
-- OpenSEO — covering indexes for foreign keys (migration 0003)
-- Speeds up ON DELETE CASCADE / SET NULL and project-scoped lookups.
-- Flagged by the Supabase performance advisor (unindexed_foreign_keys).
-- =============================================================================

-- Tenant / project cascades
create index if not exists audit_issues_page_idx        on public.audit_issues (page_id);
create index if not exists audit_issues_issue_code_idx  on public.audit_issues (issue_code);
create index if not exists jobs_project_idx             on public.jobs (project_id) where project_id is not null;
create index if not exists usage_records_project_idx    on public.usage_records (project_id) where project_id is not null;
create index if not exists usage_records_api_key_idx    on public.usage_records (api_key_id) where api_key_id is not null;
create index if not exists api_keys_project_org_idx     on public.api_keys (project_id, organization_id) where project_id is not null;
create index if not exists integrations_project_org_idx on public.integrations (project_id, organization_id) where project_id is not null;
create index if not exists keyword_tracking_project_org_idx   on public.keyword_tracking (project_id, organization_id);
create index if not exists competitor_domains_project_org_idx on public.competitor_domains (project_id, organization_id);
create index if not exists site_audits_project_org_idx        on public.site_audits (project_id, organization_id);
create index if not exists ai_analyses_project_org_idx        on public.ai_analyses (project_id, organization_id);
create index if not exists reports_project_org_idx            on public.reports (project_id, organization_id);
create index if not exists subscriptions_plan_idx             on public.subscriptions (plan_id);

-- auth.users references (user deletion → SET NULL / CASCADE)
create index if not exists organizations_created_by_idx       on public.organizations (created_by) where created_by is not null;
create index if not exists organization_members_invited_by_idx on public.organization_members (invited_by) where invited_by is not null;
create index if not exists organization_invitations_invited_by_idx  on public.organization_invitations (invited_by) where invited_by is not null;
create index if not exists organization_invitations_accepted_by_idx on public.organization_invitations (accepted_by) where accepted_by is not null;
create index if not exists projects_created_by_idx            on public.projects (created_by) where created_by is not null;
create index if not exists keyword_tracking_created_by_idx    on public.keyword_tracking (created_by) where created_by is not null;
create index if not exists competitor_domains_created_by_idx  on public.competitor_domains (created_by) where created_by is not null;
create index if not exists site_audits_triggered_by_idx       on public.site_audits (triggered_by) where triggered_by is not null;
create index if not exists api_keys_created_by_idx            on public.api_keys (created_by) where created_by is not null;
create index if not exists integrations_created_by_idx        on public.integrations (created_by) where created_by is not null;
create index if not exists ai_analyses_requested_by_idx       on public.ai_analyses (requested_by) where requested_by is not null;
create index if not exists reports_created_by_idx             on public.reports (created_by) where created_by is not null;
