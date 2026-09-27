from __future__ import annotations

from datetime import date

import pytest

from openseo_workers.config import ConfigError, Settings
from openseo_workers.providers import DataForSEOProvider, MockProvider, SerpQuery, build_serp_provider


def settings(**overrides) -> Settings:
    return Settings(database_url="postgresql://localhost/test", **overrides)


def test_falls_back_to_mock_without_credentials(caplog):
    provider = build_serp_provider(settings())
    assert isinstance(provider, MockProvider)
    assert "MOCK provider" in caplog.text


def test_uses_dataforseo_when_credentials_present():
    provider = build_serp_provider(settings(dataforseo_login="a", dataforseo_password="b"))
    assert isinstance(provider, DataForSEOProvider)


def test_half_configured_credentials_still_fall_back():
    assert isinstance(build_serp_provider(settings(dataforseo_login="a")), MockProvider)


def test_explicit_dataforseo_without_credentials_is_an_error():
    with pytest.raises(ConfigError):
        build_serp_provider(settings(serp_provider="dataforseo"))


def test_forced_mock_ignores_credentials():
    provider = build_serp_provider(
        settings(serp_provider="mock", dataforseo_login="a", dataforseo_password="b")
    )
    assert isinstance(provider, MockProvider)


def test_settings_from_env():
    s = Settings.from_env(
        {
            "DATABASE_URL": "postgresql://x",
            "QUEUES": "rank_check, keyword_metrics",
            "DATAFORSEO_LOGIN": "l",
            "DATAFORSEO_PASSWORD": "p",
            "DATAFORSEO_MODE": "live",
            "DB_ROLE": "",
            "DATAFORSEO_STOP_ON_MATCH": "false",
        }
    )
    assert s.queues == ("rank_check", "keyword_metrics")
    assert s.has_dataforseo_credentials and s.dataforseo_mode == "live"
    assert s.db_role is None and s.dataforseo_stop_on_match is False
    with pytest.raises(ConfigError):
        Settings.from_env({})
    with pytest.raises(ConfigError):
        Settings.from_env({"DATABASE_URL": "x", "DATAFORSEO_MODE": "turbo"})


async def test_mock_provider_is_deterministic_and_in_range():
    query = SerpQuery("sähköauton akku", 2246, "fi", "desktop", 100, "akkuturva.fi")
    first = await MockProvider(today=date(2026, 9, 27)).fetch_serps([query])
    again = await MockProvider(today=date(2026, 9, 27)).fetch_serps([query])
    hit, hit_again = first[query].find("akkuturva.fi"), again[query].find("akkuturva.fi")
    assert (hit and hit.rank_group) == (hit_again and hit_again.rank_group)
    if hit:
        assert 1 <= hit.rank_group <= 100
    assert first[query].provider == "mock" and first[query].cost_usd == 0
    metrics = await MockProvider().keyword_metrics(["a", "b"], 2246, "fi")
    assert [m.keyword for m in metrics.metrics] == ["a", "b"]


async def test_mock_rankings_fall_inside_the_checked_depth():
    provider = MockProvider(today=date(2026, 9, 27))
    queries = [SerpQuery(f"keyword {i}", 2246, "fi", "desktop", 20, "akkuturva.fi") for i in range(50)]
    results = await provider.fetch_serps(queries)
    ranked = [r.find("akkuturva.fi") for r in results.values()]
    positions = [hit.rank_group for hit in ranked if hit]
    assert 30 <= len(positions) <= 50  # ~80 % rank
    assert all(1 <= p <= 20 for p in positions)
