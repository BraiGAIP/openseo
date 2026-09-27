from __future__ import annotations

import json
from decimal import Decimal

import httpx
import pytest

from openseo_workers.providers import ProviderError, SerperProvider, SerpQuery
from openseo_workers.providers.serper import parse_organic

QUERY = SerpQuery("sähköauton akku", 2246, "fi", "desktop", 30, "example-ev.fi")


def make_provider(handler):
    client = httpx.AsyncClient(
        base_url="https://google.serper.dev",
        headers={"X-API-KEY": "sk"},
        transport=httpx.MockTransport(handler),
    )
    return SerperProvider("sk", client=client, cost_per_credit=Decimal("0.001"))


def page(links, **blocks):
    return {
        "organic": [{"title": f"t{i}", "link": link, "position": i} for i, link in enumerate(links, start=1)],
        **blocks,
    }


async def test_pages_until_the_tracked_domain_is_found():
    pages = {
        1: page([f"https://a{i}.fi/" for i in range(10)], answerBox={"answer": "x"}),
        2: page(
            ["https://b.fi/", "https://www.example-ev.fi/akku", "https://c.fi/"], places=[{"title": "p"}]
        ),
    }
    seen = []

    def handler(request):
        body = json.loads(request.content)
        seen.append(body)
        return httpx.Response(200, json=pages[body["page"]])

    result = (await make_provider(handler).fetch_serps([QUERY]))[QUERY]
    assert [b["page"] for b in seen] == [1, 2]  # depth 30 would allow 3 pages
    assert seen[0] == {"q": "sähköauton akku", "gl": "fi", "hl": "fi", "num": 10, "page": 1}
    hit = result.find("example-ev.fi")
    assert hit.rank_group == 12 and hit.url == "https://www.example-ev.fi/akku"
    assert result.provider == "serper" and result.pages_crawled == 2
    assert result.cost_usd == Decimal("0.002")
    assert result.serp_features == ["featured_snippet", "local_pack"]
    assert result.owns_ai_overview("example-ev.fi") is None  # Serper has no AI Overview citations


async def test_stops_at_depth_when_domain_does_not_rank():
    calls = []

    def handler(request):
        calls.append(json.loads(request.content)["page"])
        return httpx.Response(200, json=page([f"https://x{len(calls)}-{i}.fi/" for i in range(10)]))

    query = SerpQuery("akku", 2246, "fi", "desktop", 20, "example-ev.fi")
    result = (await make_provider(handler).fetch_serps([query]))[query]
    assert calls == [1, 2]
    assert result.find("example-ev.fi") is None and len(result.organic) == 20


async def test_stops_when_results_run_out():
    calls = []

    def handler(request):
        calls.append(json.loads(request.content)["page"])
        return httpx.Response(200, json=page(["https://only.fi/"] if len(calls) == 1 else []))

    result = (await make_provider(handler).fetch_serps([QUERY]))[QUERY]
    assert calls == [1, 2] and len(result.organic) == 1


@pytest.mark.parametrize(
    ("response", "retryable"),
    [
        (httpx.Response(401, json={"message": "Unauthorized."}), False),
        (httpx.Response(400, json={"message": "Not enough credits"}), False),
        (httpx.Response(429, json={"message": "Too many requests"}), True),
        (httpx.Response(502, text="bad gateway"), True),
    ],
)
async def test_error_classification(response, retryable):
    with pytest.raises(ProviderError) as exc:
        await make_provider(lambda request: response).fetch_serps([QUERY])
    assert exc.value.retryable is retryable


async def test_unsupported_location_and_no_keyword_volumes():
    provider = make_provider(lambda request: httpx.Response(200, json=page([])))
    with pytest.raises(ProviderError) as exc:
        await provider.fetch_serps([SerpQuery("x", 9999, "en")])
    assert not exc.value.retryable
    with pytest.raises(ProviderError):
        await provider.keyword_metrics(["x"], 2246, "fi")


def test_parse_organic_continues_ranking_across_pages():
    items = parse_organic(page(["https://Sub.Example.fi/a", "https://b.fi/"]), start_rank=10)
    assert [(i.rank_group, i.domain) for i in items] == [(11, "sub.example.fi"), (12, "b.fi")]
