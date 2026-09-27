-- =============================================================================
-- OpenSEO — scheduling (migration 0002)
-- Enables pg_cron where available (Supabase) and registers recurring jobs.
-- On plain PostgreSQL without pg_cron this migration is a no-op.
-- =============================================================================

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
  else
    raise notice 'pg_cron not available; skipping OpenSEO schedules';
  end if;
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Batch due keywords into rank_check jobs.
    perform cron.schedule('openseo-enqueue-rank-checks', '*/10 * * * *',
                          'select public.enqueue_due_rank_checks(100)');
    -- Partitions, cache expiry, old jobs & invitations.
    perform cron.schedule('openseo-maintenance', '17 3 * * *',
                          'select private.run_maintenance()');
    -- Push metered usage to Stripe Billing Meters.
    perform cron.schedule('openseo-stripe-usage-sync', '*/15 * * * *',
      $cmd$insert into public.jobs (queue, payload, dedupe_key)
           values ('stripe_usage_sync', '{}'::jsonb, 'stripe_usage_sync')
           on conflict do nothing$cmd$);
  end if;
end;
$$;
