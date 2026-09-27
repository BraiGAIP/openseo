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
from .fallback import FallbackSerpProvider
from .mock import MockProvider
from .serper import SerperProvider

log = logging.getLogger(__name__)

__all__ = [
    "DataForSEOProvider",
    "FallbackSerpProvider",
    "KeywordMetrics",
    "KeywordMetricsBatch",
    "MockProvider",
    "OrganicResult",
    "PendingTaskStore",
    "ProviderError",
    "SerpProvider",
    "SerpQuery",
    "SerpResult",
    "SerperProvider",
    "build_serp_provider",
]


def build_serp_provider(settings: Settings, store: PendingTaskStore | None = None) -> SerpProvider:
    """Pick the SERP provider from the configured credentials.

    auto:        DataForSEO (+ Serper fallback if SERPER_API_KEY is set) → Serper → mock
    dataforseo:  DataForSEO required (+ Serper fallback); missing credentials are an error
    serper:      Serper required (no keyword volumes)
    mock:        deterministic demo data
    """
    if settings.serp_provider == "mock":
        log.info("SERP provider: mock (forced by SERP_PROVIDER=mock)")
        return MockProvider()

    serper = (
        SerperProvider(
            settings.serper_api_key,
            base_url=settings.serper_base_url,
            cost_per_credit=settings.serper_cost_per_credit,
        )
        if settings.serper_api_key
        else None
    )
    if settings.serp_provider == "serper":
        if serper is None:
            raise ConfigError("SERP_PROVIDER=serper but SERPER_API_KEY is not set")
        log.info("SERP provider: Serper (no keyword volume data)")
        return serper

    if settings.has_dataforseo_credentials:
        dataforseo = DataForSEOProvider(
            settings.dataforseo_login or "",
            settings.dataforseo_password or "",
            mode=settings.dataforseo_mode,
            base_url=settings.dataforseo_base_url,
            store=store,
            stop_on_match=settings.dataforseo_stop_on_match,
            max_wait=settings.dataforseo_max_wait,
            poll_interval=settings.dataforseo_poll_interval,
        )
        if serper is None:
            log.info("SERP provider: DataForSEO (%s queue), no fallback", settings.dataforseo_mode)
            return dataforseo
        log.info("SERP provider: DataForSEO (%s queue) with Serper fallback", settings.dataforseo_mode)
        return FallbackSerpProvider(dataforseo, serper)
    if settings.serp_provider == "dataforseo":
        raise ConfigError("SERP_PROVIDER=dataforseo but DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD are not set")
    if serper is not None:
        log.info("SERP provider: Serper (no DataForSEO credentials; keyword volumes unavailable)")
        return serper
    log.warning(
        "No SERP provider credentials (DATAFORSEO_LOGIN / DATAFORSEO_PASSWORD, SERPER_API_KEY): "
        "falling back to the MOCK provider. Rankings written now are demo data "
        "(keyword_positions.provider = 'mock')."
    )
    return MockProvider()
