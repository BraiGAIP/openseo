"""rank_check job: fetch SERPs for a batch of tracked keywords and store positions.

Payload (written by public.enqueue_due_rank_checks() and public.request_rank_check()):
    {"keyword_ids": ["<uuid>", ...], "check_date": "YYYY-MM-DD", "manual": true?}

Manual jobs ("check now") skip today's SERP cache and ask the provider for its fastest
mode (DataForSEO live endpoint); the fresh results are cached for later jobs.

Steps
  1. Load the active keywords with their project domain.
  2. Refresh stale market metrics (search volume, CPC, competition) — shared cache first.
     A failing metrics lookup is logged and skipped; it never blocks rank tracking.
  3. Build one SerpQuery per distinct (keyword, market, device, depth, domain); reuse
     today's cached SERPs, fetch the rest from the provider, cache them.
  4. Upsert keyword_positions (the DB trigger refreshes the keyword snapshot).
  5. Meter provider usage per organization (idempotent per job, never blocks tracking).
"""

from __future__ import annotations

import logging
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

from ..db import Database, Job
from ..providers.base import (
    KeywordMetrics,
    ProviderError,
    SerpProvider,
    SerpQuery,
    SerpResult,
    normalize_keyword,
)

log = logging.getLogger(__name__)

SERP_CACHE_TTL = timedelta(days=2)


class PermanentJobError(RuntimeError):
    """The job can never succeed (bad payload); do not retry."""


@dataclass
class RankCheckContext:
    db: Database
    provider: SerpProvider
    metrics_max_age_days: int = 30


async def handle_rank_check(job: Job, ctx: RankCheckContext) -> dict[str, Any]:
    keyword_ids = [str(k) for k in job.payload.get("keyword_ids") or []]
    if not keyword_ids:
        raise PermanentJobError("rank_check payload has no keyword_ids")
    try:
        check_date = date.fromisoformat(str(job.payload.get("check_date") or date.today().isoformat()))
    except ValueError as exc:
        raise PermanentJobError(f"invalid check_date: {job.payload.get('check_date')!r}") from exc

    manual = job.payload.get("manual") is True
    keywords = await ctx.db.fetch_keywords(keyword_ids)
    if not keywords:
        return {"checked": 0, "skipped": "no active keywords"}

    await _refresh_metrics(job, ctx, keywords)

    # ---- SERPs (deduplicated, cached per day)
    query_for: dict[str, SerpQuery] = {}
    for kw in keywords:
        query_for[kw["id"]] = SerpQuery(
            keyword=kw["keyword"],
            location_code=kw["location_code"],
            language_code=kw["language_code"],
            device=kw["device"],
            depth=kw["depth"],
            target_domain=kw["domain"],
        )
    queries = list(dict.fromkeys(query_for.values()))
    keys = {q: q.cache_key(ctx.provider.name, check_date) for q in queries}
    cached = {} if manual else await ctx.db.get_cached(list(keys.values()))
    results: dict[SerpQuery, SerpResult] = {
        q: SerpResult.from_json(cached[k]) for q, k in keys.items() if k in cached
    }
    to_fetch = [q for q in queries if q not in results]
    fetched = await ctx.provider.fetch_serps(to_fetch, urgent=manual) if to_fetch else {}
    for query, result in fetched.items():
        await ctx.db.put_cached(
            keys[query],
            ctx.provider.name,
            "serp/google/organic",
            result.to_json(),
            result.cost_usd,
            SERP_CACHE_TTL,
        )
    results.update(fetched)

    # ---- positions
    rows = []
    ranked = 0
    for kw in keywords:
        result = results.get(query_for[kw["id"]])
        if result is None:
            continue
        hit = result.find(kw["domain"])
        position = hit.rank_group if hit and hit.rank_group <= 100 else None
        ranked += position is not None
        rows.append(
            {
                "keyword_id": kw["id"],
                "check_date": check_date,
                "position": position,
                "url": hit.url if hit else None,
                "title": hit.title if hit else None,
                "serp_features": result.serp_features,
                "owns_ai_overview": result.owns_ai_overview(kw["domain"]),
                "depth_checked": min(result.depth, 100),
                "provider": result.provider,
                "raw_ref": result.raw_ref,
            }
        )
    await ctx.db.upsert_positions(rows)

    # ---- usage: only SERPs this job actually paid for, attributed per organization
    pages_by_org: dict[str, int] = defaultdict(int)
    cost_by_org: dict[str, Decimal] = defaultdict(Decimal)
    project_by_org: dict[str, str] = {}
    provider_by_org: dict[str, str] = {}
    charged: set[SerpQuery] = set()
    for kw in keywords:
        query = query_for[kw["id"]]
        if query in fetched and query not in charged:
            charged.add(query)
            pages_by_org[kw["organization_id"]] += max(1, fetched[query].pages_crawled)
            cost_by_org[kw["organization_id"]] += fetched[query].cost_usd
            project_by_org.setdefault(kw["organization_id"], kw["project_id"])
            provider_by_org.setdefault(kw["organization_id"], fetched[query].provider)
    for org_id, pages in pages_by_org.items():
        await ctx.db.record_usage(
            organization_id=org_id,
            metric="serp_query",
            quantity=pages,
            idempotency_key=f"job:{job.id}:serp_query:{org_id}",
            project_id=project_by_org[org_id],
            job_id=job.id,
            provider=provider_by_org[org_id],
            provider_cost_usd=cost_by_org[org_id],
            metadata={"queue": "rank_check", "check_date": check_date.isoformat(), "scheduled": not manual},
        )

    total_cost = sum((r.cost_usd for r in fetched.values()), Decimal("0"))
    summary = {
        "provider": ctx.provider.name,
        "providers_used": sorted({r.provider for r in fetched.values()}),
        "manual": manual,
        "check_date": check_date.isoformat(),
        "checked": len(rows),
        "ranked": ranked,
        "serps_fetched": len(fetched),
        "serps_cached": len(queries) - len(to_fetch),
        "pages_crawled": sum(r.pages_crawled for r in fetched.values()),
        "cost_usd": str(total_cost),
    }
    log.info("rank_check job %s done: %s", job.id, summary)
    return summary


async def _refresh_metrics(job: Job, ctx: RankCheckContext, keywords: list[dict[str, Any]]) -> None:
    """Fill search volume / CPC / competition for keywords whose metrics are missing or stale."""
    stale_after = ctx.metrics_max_age_days
    by_market: dict[tuple[int, str], list[dict[str, Any]]] = defaultdict(list)
    for kw in keywords:
        updated = kw.get("metrics_updated_at")
        if updated is None or (date.today() - updated.date()).days >= stale_after:
            by_market[(kw["location_code"], kw["language_code"])].append(kw)

    for (location_code, language_code), group in by_market.items():
        names = list(dict.fromkeys(kw["keyword"] for kw in group))
        fresh = await ctx.db.get_fresh_metrics(names, location_code, language_code, stale_after)
        missing = [k for k in names if normalize_keyword(k) not in fresh]
        if missing:
            try:
                batch = await ctx.provider.keyword_metrics(missing, location_code, language_code)
            except ProviderError as exc:
                log.warning("keyword metrics unavailable for job %s (%s); tracking anyway", job.id, exc)
                await ctx.db.apply_metrics_to_keywords([kw["id"] for kw in group])
                continue
            # Cache "no data" too (Google Ads omits some keywords), otherwise we'd pay again every run.
            returned = {normalize_keyword(m.keyword) for m in batch.metrics}
            batch.metrics.extend(
                KeywordMetrics(keyword=k) for k in missing if normalize_keyword(k) not in returned
            )
            await ctx.db.save_metrics(batch.metrics, location_code, language_code, ctx.provider.name)
            orgs = {kw["organization_id"]: kw["project_id"] for kw in group}
            for org_id, project_id in orgs.items():
                await ctx.db.record_usage(
                    organization_id=org_id,
                    metric="keyword_lookup",
                    quantity=len([kw for kw in group if kw["organization_id"] == org_id]),
                    idempotency_key=f"job:{job.id}:keyword_lookup:{org_id}:{location_code}:{language_code}",
                    project_id=project_id,
                    job_id=job.id,
                    provider=ctx.provider.name,
                    # The provider bills per request, not per keyword: attribute it once.
                    provider_cost_usd=batch.cost_usd if org_id == next(iter(orgs)) else Decimal("0"),
                    metadata={"queue": "rank_check", "scheduled": True},
                )
        await ctx.db.apply_metrics_to_keywords([kw["id"] for kw in group])
