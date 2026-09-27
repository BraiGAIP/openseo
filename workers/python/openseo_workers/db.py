"""Database access for workers.

Every unit of work runs in its own short transaction that first drops to the
configured role (`SET LOCAL ROLE service_role`). `SET LOCAL` keeps this safe
behind Supabase's Supavisor in transaction-pooling mode, and prepared
statements are disabled for the same reason.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Iterable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import timedelta
from decimal import Decimal
from typing import Any

from psycopg import AsyncConnection, sql
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import AsyncConnectionPool

from .providers.base import KeywordMetrics


@dataclass
class Job:
    id: int
    queue: str
    organization_id: str | None
    project_id: str | None
    payload: dict[str, Any]
    attempts: int
    max_attempts: int


class Database:
    def __init__(self, pool: AsyncConnectionPool, role: str | None = "service_role"):
        self.pool = pool
        self.role = role

    @classmethod
    async def connect(cls, dsn: str, role: str | None = "service_role", max_size: int = 8) -> Database:
        pool = AsyncConnectionPool(
            dsn,
            min_size=1,
            max_size=max_size,
            kwargs={"autocommit": True, "prepare_threshold": None, "row_factory": dict_row},
            open=False,
        )
        await pool.open(wait=True)
        async with pool.connection() as conn:
            cur = await conn.execute("show server_encoding")
            encoding = (await cur.fetchone() or {}).get("server_encoding")
        if encoding != "UTF8":
            await pool.close()
            # SQL_ASCII makes psycopg return bytes for text and corrupts non-ASCII keywords.
            raise RuntimeError(f"database encoding must be UTF8 (got {encoding!r})")
        return cls(pool, role)

    async def close(self) -> None:
        await self.pool.close()

    @asynccontextmanager
    async def tx(self) -> AsyncIterator[AsyncConnection]:
        async with self.pool.connection() as conn, conn.transaction():
            if self.role:
                await conn.execute(sql.SQL("set local role {}").format(sql.Identifier(self.role)))
            yield conn

    # ------------------------------------------------------------ job queue
    async def claim_jobs(self, queues: Iterable[str], worker_id: str, limit: int) -> list[Job]:
        async with self.tx() as conn:
            cur = await conn.execute(
                "select id, queue, organization_id, project_id, payload, attempts, max_attempts"
                " from public.claim_jobs(%s, %s, %s)",
                (list(queues), worker_id, limit),
            )
            rows = await cur.fetchall()
        return [
            Job(
                id=r["id"],
                queue=r["queue"],
                organization_id=str(r["organization_id"]) if r["organization_id"] else None,
                project_id=str(r["project_id"]) if r["project_id"] else None,
                payload=r["payload"] or {},
                attempts=r["attempts"],
                max_attempts=r["max_attempts"],
            )
            for r in rows
        ]

    async def heartbeat(self, job_id: int, worker_id: str, progress: float | None = None) -> bool:
        async with self.tx() as conn:
            cur = await conn.execute(
                "select public.heartbeat_job(%s, %s, %s) as ok", (job_id, worker_id, progress)
            )
            row = await cur.fetchone()
        return bool(row and row["ok"])

    async def complete_job(self, job_id: int, worker_id: str, result: dict[str, Any]) -> None:
        async with self.tx() as conn:
            await conn.execute(
                "select public.complete_job(%s, %s, %s)", (job_id, worker_id, Jsonb(_jsonable(result)))
            )

    async def fail_job(self, job_id: int, worker_id: str, error: str, retryable: bool) -> None:
        async with self.tx() as conn:
            await conn.execute(
                "select public.fail_job(%s, %s, %s, %s)", (job_id, worker_id, error, retryable)
            )

    # ------------------------------------------------------------ keywords
    async def fetch_keywords(self, keyword_ids: list[str]) -> list[dict[str, Any]]:
        async with self.tx() as conn:
            cur = await conn.execute(
                """
                select k.id::text, k.organization_id::text, k.project_id::text, k.keyword,
                       k.location_code, k.language_code, k.device::text as device, k.depth,
                       k.search_engine::text as search_engine, k.metrics_updated_at, p.domain
                from public.keyword_tracking k
                join public.projects p on p.id = k.project_id and p.archived_at is null
                where k.id = any(%s::uuid[]) and k.is_active
                order by k.created_at
                """,
                (keyword_ids,),
            )
            return list(await cur.fetchall())

    # ------------------------------------------------------------ provider cache
    async def get_cached(self, keys: list[str]) -> dict[str, dict[str, Any]]:
        if not keys:
            return {}
        async with self.tx() as conn:
            cur = await conn.execute(
                "select cache_key, response from private.provider_cache"
                " where cache_key = any(%s) and expires_at > now()",
                (keys,),
            )
            return {r["cache_key"]: r["response"] for r in await cur.fetchall()}

    async def put_cached(
        self,
        key: str,
        provider: str,
        endpoint: str,
        response: dict[str, Any],
        cost_usd: Decimal | None,
        ttl: timedelta,
    ) -> None:
        async with self.tx() as conn:
            await conn.execute(
                """
                insert into private.provider_cache
                  (cache_key, provider, endpoint, response, cost_usd, expires_at)
                values (%s, %s, %s, %s, %s, now() + %s)
                on conflict (cache_key) do update
                  set response = excluded.response, cost_usd = excluded.cost_usd,
                      expires_at = excluded.expires_at, created_at = now()
                """,
                (key, provider, endpoint, Jsonb(_jsonable(response)), cost_usd, ttl),
            )

    async def delete_cached(self, key: str) -> None:
        async with self.tx() as conn:
            await conn.execute("delete from private.provider_cache where cache_key = %s", (key,))

    # ------------------------------------------------------------ keyword metrics
    async def get_fresh_metrics(
        self, keywords: list[str], location_code: int, language_code: str, max_age_days: int
    ) -> dict[str, dict[str, Any]]:
        async with self.tx() as conn:
            cur = await conn.execute(
                """
                select keyword_normalized, search_volume, cpc_usd, competition, monthly_searches
                from private.keyword_metrics
                where keyword_normalized = any(select public.normalize_keyword(k) from unnest(%s::text[]) k)
                  and location_code = %s and language_code = %s
                  and fetched_at > now() - make_interval(days => %s)
                """,
                (keywords, location_code, language_code, max_age_days),
            )
            return {r["keyword_normalized"]: r for r in await cur.fetchall()}

    async def save_metrics(
        self, metrics: list[KeywordMetrics], location_code: int, language_code: str, provider: str
    ) -> None:
        if not metrics:
            return
        async with self.tx() as conn, conn.cursor() as cur:
            await cur.executemany(
                """
                insert into private.keyword_metrics
                  (keyword_normalized, location_code, language_code, search_volume, cpc_usd,
                   competition, monthly_searches, provider, fetched_at)
                values (public.normalize_keyword(%s), %s, %s, %s, %s, %s, %s, %s, now())
                on conflict (keyword_normalized, location_code, language_code) do update
                  set search_volume = excluded.search_volume, cpc_usd = excluded.cpc_usd,
                      competition = excluded.competition, monthly_searches = excluded.monthly_searches,
                      provider = excluded.provider, fetched_at = excluded.fetched_at
                """,
                [
                    (
                        m.keyword,
                        location_code,
                        language_code,
                        m.search_volume,
                        m.cpc_usd,
                        m.competition,
                        Jsonb(m.monthly_searches) if m.monthly_searches else None,
                        provider,
                    )
                    for m in metrics
                ],
            )

    async def apply_metrics_to_keywords(self, keyword_ids: list[str]) -> None:
        """Copy cached market metrics onto the tracked keywords."""
        async with self.tx() as conn:
            await conn.execute(
                """
                update public.keyword_tracking k
                   set search_volume = m.search_volume, cpc_usd = m.cpc_usd, competition = m.competition,
                       monthly_searches = m.monthly_searches, metrics_updated_at = m.fetched_at
                  from private.keyword_metrics m
                 where k.id = any(%s::uuid[])
                   and m.keyword_normalized = k.keyword_normalized
                   and m.location_code = k.location_code and m.language_code = k.language_code
                """,
                (keyword_ids,),
            )

    # ------------------------------------------------------------ positions
    async def upsert_positions(self, rows: list[dict[str, Any]]) -> None:
        if not rows:
            return
        async with self.tx() as conn, conn.cursor() as cur:
            await cur.executemany(
                """
                insert into public.keyword_positions
                  (keyword_id, check_date, organization_id, project_id, checked_at, position, url, title,
                   serp_features, owns_ai_overview, depth_checked, estimated_traffic, provider, raw_ref)
                select %(keyword_id)s, %(check_date)s, k.organization_id, k.project_id, now(),
                       %(position)s::smallint, %(url)s, %(title)s, %(serp_features)s::text[],
                       %(owns_ai_overview)s::boolean,
                       %(depth_checked)s::smallint,
                       round(public.ctr_for_position(%(position)s::integer)
                             * coalesce(k.search_volume, 0), 2),
                       %(provider)s, %(raw_ref)s
                  from public.keyword_tracking k where k.id = %(keyword_id)s
                on conflict (keyword_id, check_date) do update
                  set checked_at = excluded.checked_at, position = excluded.position, url = excluded.url,
                      title = excluded.title, serp_features = excluded.serp_features,
                      owns_ai_overview = excluded.owns_ai_overview, depth_checked = excluded.depth_checked,
                      estimated_traffic = excluded.estimated_traffic, provider = excluded.provider,
                      raw_ref = excluded.raw_ref
                """,
                rows,
            )

    # ------------------------------------------------------------ usage
    async def record_usage(
        self,
        *,
        organization_id: str,
        metric: str,
        quantity: int,
        idempotency_key: str,
        project_id: str | None = None,
        job_id: int | None = None,
        provider: str | None = None,
        provider_cost_usd: Decimal | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        async with self.tx() as conn:
            await conn.execute(
                """
                select * from public.record_usage(
                  p_org_id => %s, p_metric => %s::public.usage_metric, p_quantity => %s,
                  p_idempotency_key => %s, p_project_id => %s, p_source => 'worker',
                  p_job_id => %s, p_provider => %s, p_provider_cost_usd => %s,
                  p_enforce_quota => false, p_metadata => %s)
                """,
                (
                    organization_id,
                    metric,
                    quantity,
                    idempotency_key,
                    project_id,
                    job_id,
                    provider,
                    provider_cost_usd,
                    Jsonb(metadata or {}),
                ),
            )


class DbPendingTaskStore:
    """PendingTaskStore backed by private.provider_cache (survives worker restarts)."""

    def __init__(self, db: Database, ttl: timedelta = timedelta(days=3)):
        self.db = db
        self.ttl = ttl

    async def get(self, key: str) -> str | None:
        hit = (await self.db.get_cached([key])).get(key)
        return hit.get("task_id") if hit else None

    async def put(self, key: str, task_id: str) -> None:
        await self.db.put_cached(key, "dataforseo", "task_post", {"task_id": task_id}, None, self.ttl)

    async def delete(self, key: str) -> None:
        await self.db.delete_cached(key)


def _jsonable(value: Any) -> Any:
    return json.loads(json.dumps(value, default=str))
