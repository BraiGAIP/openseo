"""Provider-neutral data model for SERP and keyword data."""

from __future__ import annotations

import hashlib
from dataclasses import asdict, dataclass, field
from datetime import date
from decimal import Decimal
from typing import Any, Protocol


class ProviderError(RuntimeError):
    """A provider call failed. `retryable` decides whether the job is retried.

    `pending` marks work that was accepted but is not finished yet (queued provider tasks):
    retrying later is cheaper than falling back to another provider.
    """

    def __init__(
        self,
        message: str,
        *,
        retryable: bool = True,
        status_code: int | None = None,
        pending: bool = False,
    ):
        super().__init__(message)
        self.retryable = retryable
        self.status_code = status_code
        self.pending = pending


def normalize_domain(value: str) -> str:
    value = value.strip().lower()
    for prefix in ("https://", "http://"):
        if value.startswith(prefix):
            value = value[len(prefix) :]
    value = value.split("/", 1)[0].split(":", 1)[0]
    return value[4:] if value.startswith("www.") else value


def domain_matches(candidate: str | None, target: str) -> bool:
    """True when `candidate` is `target` or one of its subdomains."""
    if not candidate:
        return False
    candidate, target = normalize_domain(candidate), normalize_domain(target)
    return candidate == target or candidate.endswith("." + target)


def normalize_keyword(value: str) -> str:
    return " ".join(value.lower().split())


@dataclass(frozen=True)
class SerpQuery:
    keyword: str
    location_code: int
    language_code: str
    device: str = "desktop"
    depth: int = 100
    # Domain whose ranking we need; lets providers stop crawling once it is found.
    target_domain: str | None = None

    def cache_key(self, provider: str, check_date: date) -> str:
        parts = [
            provider,
            normalize_keyword(self.keyword),
            str(self.location_code),
            self.language_code,
            self.device,
            str(self.depth),
            normalize_domain(self.target_domain) if self.target_domain else "",
            check_date.isoformat(),
        ]
        return "serp:" + hashlib.sha256("|".join(parts).encode()).hexdigest()


@dataclass
class OrganicResult:
    rank_group: int
    rank_absolute: int
    domain: str
    url: str
    title: str | None = None


@dataclass
class SerpResult:
    provider: str
    organic: list[OrganicResult] = field(default_factory=list)
    item_types: list[str] = field(default_factory=list)
    ai_overview_domains: list[str] = field(default_factory=list)
    pages_crawled: int = 1
    depth: int = 10
    cost_usd: Decimal = Decimal("0")
    raw_ref: str | None = None

    def find(self, domain: str) -> OrganicResult | None:
        """Best (lowest) organic rank of `domain` or its subdomains."""
        hits = [r for r in self.organic if domain_matches(r.domain, domain)]
        return min(hits, key=lambda r: r.rank_group) if hits else None

    def owns_ai_overview(self, domain: str) -> bool | None:
        if "ai_overview" not in self.item_types:
            return None
        return any(domain_matches(d, domain) for d in self.ai_overview_domains)

    @property
    def serp_features(self) -> list[str]:
        return sorted({t for t in self.item_types if t != "organic"})

    def to_json(self) -> dict[str, Any]:
        data = asdict(self)
        data["cost_usd"] = str(self.cost_usd)
        return data

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> SerpResult:
        return cls(
            provider=data["provider"],
            organic=[OrganicResult(**o) for o in data.get("organic", [])],
            item_types=list(data.get("item_types", [])),
            ai_overview_domains=list(data.get("ai_overview_domains", [])),
            pages_crawled=int(data.get("pages_crawled", 1)),
            depth=int(data.get("depth", 10)),
            cost_usd=Decimal(str(data.get("cost_usd", "0"))),
            raw_ref=data.get("raw_ref"),
        )


@dataclass
class KeywordMetrics:
    keyword: str
    search_volume: int | None = None
    cpc_usd: float | None = None
    # 0–1 (Google Ads competition index / 100)
    competition: float | None = None
    monthly_searches: list[dict[str, int]] | None = None


@dataclass
class KeywordMetricsBatch:
    metrics: list[KeywordMetrics]
    cost_usd: Decimal = Decimal("0")


class PendingTaskStore(Protocol):
    """Persists provider task ids so a retried job resumes instead of paying twice."""

    async def get(self, key: str) -> str | None: ...

    async def put(self, key: str, task_id: str) -> None: ...

    async def delete(self, key: str) -> None: ...


class SerpProvider(Protocol):
    name: str

    async def fetch_serps(
        self, queries: list[SerpQuery], *, urgent: bool = False
    ) -> dict[SerpQuery, SerpResult]:
        """Fetch SERPs. `urgent` (manual "check now") trades cost for latency where the provider can."""
        ...

    async def keyword_metrics(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> KeywordMetricsBatch: ...

    async def aclose(self) -> None: ...
