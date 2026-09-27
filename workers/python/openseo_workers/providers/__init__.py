"""SERP / keyword data providers and the selection logic between them."""

from __future__ import annotations

import logging

from ..config import ConfigError, Settings
from .base import (
    KeywordMetrics,
    KeywordMetricsBatch,
    OrganicResult,
    PendingTaskStore,
    ProviderError,
    SerpProvider,
    SerpQuery,
    SerpResult,
)
from .dataforseo import DataForSEOProvider
from .mock import MockProvider

log = logging.getLogger(__name__)

__all__ = [
    "DataForSEOProvider",
    "KeywordMetrics",
    "KeywordMetricsBatch",
    "MockProvider",
    "OrganicResult",
    "PendingTaskStore",
    "ProviderError",
    "SerpProvider",
    "SerpQuery",
    "SerpResult",
    "build_serp_provider",
]


def build_serp_provider(settings: Settings, store: PendingTaskStore | None = None) -> SerpProvider:
    """DataForSEO when credentials are configured, otherwise the deterministic mock provider.

    SERP_PROVIDER=dataforseo makes missing credentials a hard error (production);
    SERP_PROVIDER=mock forces the mock provider (development, demos).
    """
    if settings.serp_provider == "mock":
        log.info("SERP provider: mock (forced by SERP_PROVIDER=mock)")
        return MockProvider()
    if settings.has_dataforseo_credentials:
        log.info("SERP provider: DataForSEO (%s queue)", settings.dataforseo_mode)
        return DataForSEOProvider(
            settings.dataforseo_login or "",
            settings.dataforseo_password or "",
            mode=settings.dataforseo_mode,
            base_url=settings.dataforseo_base_url,
            store=store,
            stop_on_match=settings.dataforseo_stop_on_match,
            max_wait=settings.dataforseo_max_wait,
            poll_interval=settings.dataforseo_poll_interval,
        )
    if settings.serp_provider == "dataforseo":
        raise ConfigError("SERP_PROVIDER=dataforseo but DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD are not set")
    log.warning(
        "DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD not set: falling back to the MOCK provider. "
        "Rankings written now are demo data (keyword_positions.provider = 'mock')."
    )
    return MockProvider()
