"""Primary → secondary SERP provider chain (e.g. DataForSEO → Serper)."""

from __future__ import annotations

import logging

from .base import KeywordMetricsBatch, ProviderError, SerpProvider, SerpQuery, SerpResult

log = logging.getLogger(__name__)


class FallbackSerpProvider:
    """Uses `primary`; if it fails, fetches the same SERPs from `secondary`.

    Results keep the provider that actually produced them (SerpResult.provider), so positions
    fetched through the fallback are stored as e.g. provider = 'serper'. The chain reports the
    primary's name, which keeps SERP cache keys stable.

    Not a fallback case: queued primary tasks that simply aren't finished (`pending`) — the
    retried job resumes them, which is cheaper than paying a second provider.
    Keyword metrics only come from the primary (Serper has no search volume).
    """

    def __init__(self, primary: SerpProvider, secondary: SerpProvider):
        self.primary = primary
        self.secondary = secondary
        self.name = primary.name

    async def fetch_serps(
        self, queries: list[SerpQuery], *, urgent: bool = False
    ) -> dict[SerpQuery, SerpResult]:
        try:
            return await self.primary.fetch_serps(queries, urgent=urgent)
        except ProviderError as exc:
            if exc.pending:
                raise
            log.warning(
                "%s failed (%s); fetching %d SERP(s) from %s instead",
                self.primary.name,
                exc,
                len(queries),
                self.secondary.name,
            )
            try:
                return await self.secondary.fetch_serps(queries, urgent=urgent)
            except ProviderError as fallback_exc:
                # Retry if either provider may recover.
                raise ProviderError(
                    f"{self.primary.name}: {exc}; {self.secondary.name}: {fallback_exc}",
                    retryable=exc.retryable or fallback_exc.retryable,
                ) from fallback_exc

    async def keyword_metrics(
        self, keywords: list[str], location_code: int, language_code: str
    ) -> KeywordMetricsBatch:
        return await self.primary.keyword_metrics(keywords, location_code, language_code)

    async def aclose(self) -> None:
        await self.primary.aclose()
        await self.secondary.aclose()
