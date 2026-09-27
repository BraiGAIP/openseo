"""Serper.dev Google Search API — fallback SERP provider (architecture decision D6).

POST https://google.serper.dev/search  (header X-API-KEY)
    {"q": ..., "gl": "fi", "hl": "fi", "num": 10, "page": 1}
Response: {"organic": [{"title", "link", "position", ...}], "answerBox", "peopleAlsoAsk", ..., "credits"}

Google returns ~10 results per page, so we page through results ourselves and stop at the
page that contains the tracked domain (like DataForSEO's stop_crawl_on_match). Each page is
one Serper credit.

Limitations compared to DataForSEO: desktop results only (no device parameter), countries
only (location_code is mapped to a Google country code), no AI Overview citations and no
keyword search volume.
"""

from __future__ import annotations

import asyncio
import logging
from decimal import Decimal
from typing import Any
from urllib.parse import urlsplit

import httpx

from .base import (
    KeywordMetricsBatch,
    OrganicResult,
    ProviderError,
    SerpQuery,
    SerpResult,
    domain_matches,
)

log = logging.getLogger(__name__)

PAGE_SIZE = 10
CONCURRENCY = 5

# Google Ads location criteria id → Google country code (gl). Keep in sync with
# SEARCH_LOCATIONS in packages/shared/src/index.ts.
COUNTRY_BY_LOCATION = {
    2840: "us",
    2826: "gb",
    2124: "ca",
    2036: "au",
    2276: "de",
    2246: "fi",
    2752: "se",
    2578: "no",
    2208: "dk",
}

# Serper response blocks → DataForSEO item types, so SERP features look the same in the UI.
FEATURE_BY_BLOCK = {
    "answerBox": "featured_snippet",
    "knowledgeGraph": "knowledge_graph",
    "peopleAlsoAsk": "people_also_ask",
    "topStories": "top_stories",
    "images": "images",
    "videos": "video",
    "places": "local_pack",
    "relatedSearches": "related_searches",
}


class SerperProvider:
    name = "serper"

    def __init__(
        self,
        api_key: str,
        *,
        base_url: str = "https://google.serper.dev",
        cost_per_credit: Decimal = Decimal("0.001"),
        client: httpx.AsyncClient | None = None,
    ):
        self._cost_per_credit = cost_per_credit
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=base_url,
            headers={"X-API-KEY": api_key, "Content-Type": "application/json"},
            timeout=httpx.Timeout(30.0, connect=10.0),
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def _search(self, payload: dict[str, Any]) -> dict[str, Any]:
        try:
            response = await self._client.post("/search", json=payload)
        except httpx.HTTPError as exc:
            raise ProviderError(f"Serper request failed: {exc}", retryable=True) from exc
        if response.status_code in (401, 403):
            raise ProviderError(
                "Serper rejected the API key", retryable=False, status_code=response.status_code
            )
        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderError(f"Serper HTTP {response.status_code}", retryable=True)
        if response.status_code >= 400:
            # e.g. out of credits or invalid parameters: retrying won't help.
            raise ProviderError(
                f"Serper HTTP {response.status_code}: {response.text[:200]}",
                retryable=False,
                status_code=response.status_code,
            )
        try:
            return response.json()
        except ValueError as exc:
            raise ProviderError("Serper returned non-JSON") from exc

    async def fetch_serps(
        self, queries: list[SerpQuery], *, urgent: bool = False
    ) -> dict[SerpQuery, SerpResult]:
        unique = list(dict.fromkeys(queries))
        semaphore = asyncio.Semaphore(CONCURRENCY)

        async def one(query: SerpQuery) -> SerpResult:
            async with semaphore:
                return await self._fetch(query)

        results = await asyncio.gather(*(one(q) for q in unique))
        return dict(zip(unique, results, strict=True))

    async def _fetch(self, query: SerpQuery) -> SerpResult:
        country = COUNTRY_BY_LOCATION.get(query.location_code)
        if country is None:
            raise ProviderError(f"Serper: unsupported location_code {query.location_code}", retryable=False)

        organic: list[OrganicResult] = []
        features: set[str] = set()
        credits = 0
        pages = 0
        max_pages = max(1, -(-min(query.depth, 100) // PAGE_SIZE))
        for page in range(1, max_pages + 1):
            body = await self._search(
                {"q": query.keyword, "gl": country, "hl": query.language_code, "num": PAGE_SIZE, "page": page}
            )
            pages += 1
            credits += int(body.get("credits") or 1)
            features.update(feature for block, feature in FEATURE_BY_BLOCK.items() if body.get(block))
            page_items = parse_organic(body, start_rank=len(organic))
            organic.extend(page_items)
            if not page_items or len(organic) >= query.depth:
                break
            if query.target_domain and any(domain_matches(r.domain, query.target_domain) for r in page_items):
                break

        return SerpResult(
            provider=self.name,
            organic=organic,
            item_types=["organic", *sorted(features)],
            ai_overview_domains=[],
            pages_crawled=pages,
            depth=query.depth,
            cost_usd=self._cost_per_credit * credits,
            raw_ref=None,
        )

    async def keyword_metrics(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> KeywordMetricsBatch:
        raise ProviderError("Serper has no keyword search volume data", retryable=False)


def parse_organic(body: dict[str, Any], start_rank: int = 0) -> list[OrganicResult]:
    """Organic results of one page, ranked after the `start_rank` results of earlier pages."""
    items = [i for i in body.get("organic") or [] if i and i.get("link")]
    items.sort(key=lambda i: i.get("position") or 0)
    results = []
    for offset, item in enumerate(items, start=1):
        rank = start_rank + offset
        results.append(
            OrganicResult(
                rank_group=rank,
                rank_absolute=rank,
                domain=(urlsplit(item["link"]).hostname or "").lower(),
                url=item["link"],
                title=item.get("title"),
            )
        )
    return results
