"""Deterministic offline provider used when no API credentials are configured.

Rows it produces are stored with provider = 'mock' so the UI can flag them as demo data.
"""

from __future__ import annotations

import hashlib
import math
from datetime import date
from decimal import Decimal

from .base import (
    KeywordMetrics,
    KeywordMetricsBatch,
    OrganicResult,
    SerpQuery,
    SerpResult,
    normalize_domain,
    normalize_keyword,
)

_FEATURES = ["people_also_ask", "featured_snippet", "local_pack", "video", "images", "ai_overview"]


def _seed(*parts: str) -> int:
    return int.from_bytes(hashlib.sha256("|".join(parts).encode()).digest()[:8], "big")


class MockProvider:
    name = "mock"

    def __init__(self, today: date | None = None):
        self._today = today

    def _position(self, query: SerpQuery, day: date) -> int | None:
        target = normalize_domain(query.target_domain or "example.com")
        seed = _seed(normalize_keyword(query.keyword), target, str(query.location_code), query.device)
        if seed % 5 == 0:  # ~20 % of keywords don't rank
            return None
        # Keep demo rankings inside the checked depth so dashboards show a realistic spread.
        base = 1 + seed % max(1, min(query.depth, 60) - 3)
        drift = round(3 * math.sin(day.toordinal() / 5 + seed % 97))
        position = max(1, min(100, base + drift))
        return position if position <= query.depth else None

    async def fetch_serps(self, queries: list[SerpQuery]) -> dict[SerpQuery, SerpResult]:
        day = self._today or date.today()
        results: dict[SerpQuery, SerpResult] = {}
        for query in queries:
            position = self._position(query, day)
            seed = _seed(normalize_keyword(query.keyword), str(query.location_code))
            organic = [
                OrganicResult(
                    rank_group=i,
                    rank_absolute=i,
                    domain=f"site{(seed + i) % 997}.example",
                    url=f"https://site{(seed + i) % 997}.example/{i}",
                )
                for i in range(1, min(query.depth, 100) + 1)
            ]
            if position is not None and query.target_domain:
                domain = normalize_domain(query.target_domain)
                slug = normalize_keyword(query.keyword).replace(" ", "-")
                organic[position - 1] = OrganicResult(
                    rank_group=position, rank_absolute=position, domain=domain, url=f"https://{domain}/{slug}"
                )
            features = [f for i, f in enumerate(_FEATURES) if (seed >> i) & 1]
            results[query] = SerpResult(
                provider=self.name,
                organic=organic,
                item_types=["organic", *features],
                ai_overview_domains=[organic[0].domain] if "ai_overview" in features else [],
                pages_crawled=math.ceil(len(organic) / 10),
                depth=query.depth,
                cost_usd=Decimal("0"),
            )
        return results

    async def keyword_metrics(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> KeywordMetricsBatch:
        metrics = []
        for keyword in keywords:
            seed = _seed(normalize_keyword(keyword), str(location_code), language_code)
            volume = [10, 50, 140, 390, 880, 1900, 5400, 12100][seed % 8]
            metrics.append(
                KeywordMetrics(
                    keyword=keyword,
                    search_volume=volume,
                    cpc_usd=round((seed % 500) / 100, 2),
                    competition=round((seed % 100) / 100, 2),
                    monthly_searches=None,
                )
            )
        return KeywordMetricsBatch(metrics=metrics, cost_usd=Decimal("0"))

    async def aclose(self) -> None:
        return None
