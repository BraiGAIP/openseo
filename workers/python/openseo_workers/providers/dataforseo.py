"""DataForSEO REST API v3 provider.

SERP: Google Organic, *advanced* results.
  - standard mode (default, cheapest): POST /v3/serp/google/organic/task_post (≤100 tasks per call),
    then GET /v3/serp/google/organic/task_get/advanced/{id} until the task is done.
  - live mode: POST /v3/serp/google/organic/live/advanced (one task per call, several in parallel).
    Also used for urgent (manual "check now") requests regardless of the configured mode.
  `stop_crawl_on_match` stops crawling once the tracked domain is found, so only the pages
  up to our ranking are billed.
Keyword data: POST /v3/keywords_data/google_ads/search_volume/live (≤1000 keywords, billed per call)
and POST /v3/dataforseo_labs/google/bulk_keyword_difficulty/live (≤1000 keywords, 0–100 scale).

Credentials: DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD (HTTP Basic auth).
"""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Awaitable, Callable
from datetime import date
from decimal import Decimal
from typing import Any

import httpx

from .base import (
    KeywordMetrics,
    KeywordMetricsBatch,
    OrganicResult,
    PendingTaskStore,
    ProviderError,
    SerpQuery,
    SerpResult,
    normalize_domain,
    normalize_keyword,
)

log = logging.getLogger(__name__)

OK = 20000
TASK_CREATED = 20100
TASK_HANDED = 40601
TASK_IN_QUEUE = 40602
PENDING_CODES = {TASK_HANDED, TASK_IN_QUEUE}

MAX_TASKS_PER_POST = 100
LIVE_CONCURRENCY = 8
MAX_KEYWORDS_PER_VOLUME_CALL = 1000
MAX_KEYWORDS_PER_DIFFICULTY_CALL = 1000
# Google Ads limits for the search volume endpoint.
MAX_KEYWORD_CHARS = 80
MAX_KEYWORD_WORDS = 10


def _retryable_status(code: int | None) -> bool:
    # 5xxxx = DataForSEO internal errors; 4xxxx = request/account problems (auth, balance, params).
    return code is None or code >= 50000


class DataForSEOProvider:
    name = "dataforseo"

    def __init__(
        self,
        login: str,
        password: str,
        *,
        mode: str = "standard",
        base_url: str = "https://api.dataforseo.com",
        store: PendingTaskStore | None = None,
        stop_on_match: bool = True,
        keyword_difficulty: bool = True,
        max_wait: float = 900.0,
        poll_interval: float = 10.0,
        client: httpx.AsyncClient | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        clock: Callable[[], float] = time.monotonic,
        check_date: date | None = None,
    ):
        if mode not in {"standard", "live"}:
            raise ValueError(f"unknown DataForSEO mode {mode!r}")
        self.mode = mode
        self._store = store
        self._stop_on_match = stop_on_match
        self._keyword_difficulty = keyword_difficulty
        self._max_wait = max_wait
        self._poll_interval = poll_interval
        self._sleep = sleep
        self._clock = clock
        self._check_date = check_date
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=base_url,
            auth=httpx.BasicAuth(login, password),
            timeout=httpx.Timeout(60.0, connect=10.0),
            headers={"User-Agent": "BraiSEO-worker/0.1 (+https://brai.build)"},
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    # ------------------------------------------------------------------ HTTP
    async def _request(self, method: str, path: str, json: Any = None) -> dict[str, Any]:
        try:
            response = await self._client.request(method, path, json=json)
        except httpx.HTTPError as exc:
            raise ProviderError(f"DataForSEO request failed: {exc}", retryable=True) from exc
        if response.status_code in (401, 403):
            raise ProviderError("DataForSEO rejected the credentials", retryable=False, status_code=40100)
        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderError(f"DataForSEO HTTP {response.status_code}", retryable=True)
        try:
            body = response.json()
        except ValueError as exc:
            raise ProviderError(f"DataForSEO returned non-JSON (HTTP {response.status_code})") from exc
        code = body.get("status_code")
        if code != OK:
            raise ProviderError(
                f"DataForSEO error {code}: {body.get('status_message')}",
                retryable=_retryable_status(code),
                status_code=code,
            )
        return body

    # ------------------------------------------------------------------ SERP
    def _task_payload(self, query: SerpQuery, tag: str | None = None) -> dict[str, Any]:
        task: dict[str, Any] = {
            "keyword": query.keyword,
            "location_code": query.location_code,
            "language_code": query.language_code,
            "device": query.device,
            "depth": query.depth,
        }
        if tag:
            task["tag"] = tag[:255]
        if self._stop_on_match and query.target_domain:
            task["stop_crawl_on_match"] = [
                {"match_value": normalize_domain(query.target_domain), "match_type": "with_subdomains"}
            ]
        return task

    def _store_key(self, query: SerpQuery) -> str:
        return "dataforseo:pending:" + query.cache_key(self.name, self._check_date or date.today())

    async def fetch_serps(
        self, queries: list[SerpQuery], *, urgent: bool = False
    ) -> dict[SerpQuery, SerpResult]:
        unique = list(dict.fromkeys(queries))
        if self.mode == "live" or urgent:
            return await self._fetch_live_many(unique)
        return await self._fetch_standard(unique)

    async def _fetch_live_many(self, queries: list[SerpQuery]) -> dict[SerpQuery, SerpResult]:
        semaphore = asyncio.Semaphore(LIVE_CONCURRENCY)

        async def one(query: SerpQuery) -> SerpResult:
            async with semaphore:
                return await self._fetch_live(query)

        results = await asyncio.gather(*(one(q) for q in queries))
        return dict(zip(queries, results, strict=True))

    async def _fetch_live(self, query: SerpQuery) -> SerpResult:
        body = await self._request(
            "POST", "/v3/serp/google/organic/live/advanced", [self._task_payload(query)]
        )
        task = (body.get("tasks") or [None])[0]
        if not task or task.get("status_code") != OK:
            code = task.get("status_code") if task else None
            raise ProviderError(
                f"live task failed: {task.get('status_message') if task else 'no task'}",
                retryable=_retryable_status(code),
                status_code=code,
            )
        return parse_serp_task(task, query)

    async def _fetch_standard(self, queries: list[SerpQuery]) -> dict[SerpQuery, SerpResult]:
        task_ids: dict[SerpQuery, str] = {}
        to_post: list[SerpQuery] = []
        for query in queries:
            existing = await self._store.get(self._store_key(query)) if self._store else None
            if existing:
                task_ids[query] = existing
            else:
                to_post.append(query)

        for start in range(0, len(to_post), MAX_TASKS_PER_POST):
            chunk = to_post[start : start + MAX_TASKS_PER_POST]
            payload = [self._task_payload(q, tag=str(i)) for i, q in enumerate(chunk)]
            body = await self._request("POST", "/v3/serp/google/organic/task_post", payload)
            for task in body.get("tasks") or []:
                query = chunk[int((task.get("data") or {}).get("tag", -1))]
                if task.get("status_code") != TASK_CREATED or not task.get("id"):
                    code = task.get("status_code")
                    raise ProviderError(
                        f"task_post failed for {query.keyword!r}: {code} {task.get('status_message')}",
                        retryable=_retryable_status(code),
                        status_code=code,
                    )
                task_ids[query] = task["id"]
                if self._store:
                    await self._store.put(self._store_key(query), task["id"])

        results: dict[SerpQuery, SerpResult] = {}
        pending = dict(task_ids)
        deadline = self._clock() + self._max_wait
        while pending:
            for query, task_id in list(pending.items()):
                body = await self._request("GET", f"/v3/serp/google/organic/task_get/advanced/{task_id}")
                task = (body.get("tasks") or [{}])[0]
                code = task.get("status_code")
                if code == OK:
                    results[query] = parse_serp_task(task, query)
                    del pending[query]
                    if self._store:
                        await self._store.delete(self._store_key(query))
                elif code in PENDING_CODES:
                    continue
                else:
                    if self._store:
                        await self._store.delete(self._store_key(query))
                    raise ProviderError(
                        f"task {task_id} failed: {code} {task.get('status_message')}",
                        retryable=_retryable_status(code),
                        status_code=code,
                    )
            if pending:
                if self._clock() >= deadline:
                    # Task ids stay in the store: the retried job resumes polling without re-posting.
                    raise ProviderError(
                        f"{len(pending)} DataForSEO task(s) still queued after {self._max_wait:.0f}s",
                        retryable=True,
                        pending=True,
                    )
                await self._sleep(self._poll_interval)
        return results

    # ------------------------------------------------------------ keywords
    async def keyword_metrics(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> KeywordMetricsBatch:
        eligible = [
            k
            for k in dict.fromkeys(keywords)
            if len(k) <= MAX_KEYWORD_CHARS and len(k.split()) <= MAX_KEYWORD_WORDS
        ]
        metrics: list[KeywordMetrics] = []
        cost = Decimal("0")
        for start in range(0, len(eligible), MAX_KEYWORDS_PER_VOLUME_CALL):
            chunk = eligible[start : start + MAX_KEYWORDS_PER_VOLUME_CALL]
            body = await self._request(
                "POST",
                "/v3/keywords_data/google_ads/search_volume/live",
                [{"keywords": chunk, "location_code": location_code, "language_code": language_code}],
            )
            cost += Decimal(str(body.get("cost") or 0))
            for task in body.get("tasks") or []:
                if task.get("status_code") != OK:
                    code = task.get("status_code")
                    raise ProviderError(
                        f"search_volume failed: {code} {task.get('status_message')}",
                        retryable=_retryable_status(code),
                        status_code=code,
                    )
                metrics.extend(parse_search_volume_item(item) for item in task.get("result") or [] if item)

        if self._keyword_difficulty and eligible:
            difficulty, kd_cost = await self._keyword_difficulties(eligible, location_code, language_code)
            cost += kd_cost
            by_keyword = {normalize_keyword(m.keyword): m for m in metrics}
            for keyword, value in difficulty.items():
                entry = by_keyword.get(keyword)
                if entry is None:
                    entry = by_keyword[keyword] = KeywordMetrics(keyword=keyword)
                    metrics.append(entry)
                entry.keyword_difficulty = value
        return KeywordMetricsBatch(metrics=metrics, cost_usd=cost)

    async def _keyword_difficulties(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> tuple[dict[str, int], Decimal]:
        """Keyword difficulty from DataForSEO Labs, keyed by normalized keyword.

        A permanent failure (e.g. Labs not enabled for the account) only drops difficulty;
        a temporary one is raised so the whole metrics refresh is retried on the next run.
        """
        found: dict[str, int] = {}
        cost = Decimal("0")
        for start in range(0, len(keywords), MAX_KEYWORDS_PER_DIFFICULTY_CALL):
            chunk = keywords[start : start + MAX_KEYWORDS_PER_DIFFICULTY_CALL]
            try:
                body = await self._request(
                    "POST",
                    "/v3/dataforseo_labs/google/bulk_keyword_difficulty/live",
                    [{"keywords": chunk, "location_code": location_code, "language_code": language_code}],
                )
            except ProviderError as exc:
                if exc.retryable:
                    raise
                log.warning("keyword difficulty unavailable (%s); continuing without it", exc)
                return found, cost
            cost += Decimal(str(body.get("cost") or 0))
            for task in body.get("tasks") or []:
                if task.get("status_code") != OK:
                    code = task.get("status_code")
                    if _retryable_status(code):
                        raise ProviderError(f"keyword difficulty failed: {code}", status_code=code)
                    log.warning("keyword difficulty failed: %s %s", code, task.get("status_message"))
                    return found, cost
                for result in task.get("result") or []:
                    for item in (result or {}).get("items") or []:
                        if item and item.get("keyword") and item.get("keyword_difficulty") is not None:
                            found[normalize_keyword(item["keyword"])] = int(item["keyword_difficulty"])
        return found, cost


# ---------------------------------------------------------------- parsing
def parse_serp_task(task: dict[str, Any], query: SerpQuery) -> SerpResult:
    result = (task.get("result") or [None])[0] or {}
    items = [i for i in (result.get("items") or []) if i]
    organic = [
        OrganicResult(
            rank_group=int(i["rank_group"]),
            rank_absolute=int(i.get("rank_absolute") or i["rank_group"]),
            domain=i.get("domain") or "",
            url=i.get("url") or "",
            title=i.get("title"),
        )
        for i in items
        if i.get("type") == "organic" and i.get("rank_group") is not None
    ]
    ai_domains: list[str] = []
    for item in items:
        if item.get("type") != "ai_overview":
            continue
        refs = list(item.get("references") or [])
        for sub in item.get("items") or []:
            refs.extend((sub or {}).get("references") or [])
        ai_domains.extend(r["domain"] for r in refs if r and r.get("domain"))
    item_types = list(result.get("item_types") or sorted({i.get("type") for i in items if i.get("type")}))
    pages = int(result.get("pages_count") or max(1, -(-len(organic) // 10)))
    return SerpResult(
        provider=DataForSEOProvider.name,
        organic=organic,
        item_types=item_types,
        ai_overview_domains=sorted(set(ai_domains)),
        pages_crawled=pages,
        depth=query.depth,
        cost_usd=Decimal(str(task.get("cost") or 0)),
        raw_ref=task.get("id"),
    )


def parse_search_volume_item(item: dict[str, Any]) -> KeywordMetrics:
    index = item.get("competition_index")
    monthly = [
        {"year": m["year"], "month": m["month"], "search_volume": m.get("search_volume")}
        for m in item.get("monthly_searches") or []
        if m
    ]
    return KeywordMetrics(
        keyword=item.get("keyword") or "",
        search_volume=item.get("search_volume"),
        cpc_usd=item.get("cpc"),
        competition=None if index is None else round(index / 100, 3),
        monthly_searches=monthly or None,
    )
