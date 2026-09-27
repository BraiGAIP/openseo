from __future__ import annotations

import base64
import json
from decimal import Decimal

import httpx
import pytest

from openseo_workers.providers import DataForSEOProvider, ProviderError, SerpQuery
from openseo_workers.providers.dataforseo import parse_search_volume_item, parse_serp_task

QUERY = SerpQuery("ev battery warranty", 2840, "en", "desktop", 100, "example-ev.com")


class MemoryStore:
    def __init__(self):
        self.data: dict[str, str] = {}

    async def get(self, key):
        return self.data.get(key)

    async def put(self, key, task_id):
        self.data[key] = task_id

    async def delete(self, key):
        self.data.pop(key, None)


def make_provider(handler, *, mode="standard", store=None, max_wait=900.0):
    client = httpx.AsyncClient(
        base_url="https://api.dataforseo.com",
        auth=httpx.BasicAuth("login@example.com", "secret"),
        transport=httpx.MockTransport(handler),
    )
    sleeps: list[float] = []

    async def fake_sleep(seconds: float) -> None:
        sleeps.append(seconds)

    clock = iter(range(0, 10_000, 10))
    provider = DataForSEOProvider(
        "login@example.com",
        "secret",
        mode=mode,
        client=client,
        store=store,
        max_wait=max_wait,
        poll_interval=10,
        sleep=fake_sleep,
        clock=lambda: next(clock),
    )
    return provider, sleeps


def envelope(tasks, cost=0.0):
    return {"status_code": 20000, "status_message": "Ok.", "cost": cost, "tasks": tasks}


def test_parse_serp_task_finds_best_subdomain_rank(serp_fixture):
    result = parse_serp_task(serp_fixture["tasks"][0], QUERY)
    hit = result.find("example-ev.com")
    assert hit is not None and hit.rank_group == 12  # blog. subdomain beats www. at 15
    assert hit.url == "https://blog.example-ev.com/ev-battery-life"
    assert result.pages_crawled == 2
    assert result.cost_usd == Decimal("0.00105")
    assert result.serp_features == ["ai_overview", "people_also_ask"]
    assert result.owns_ai_overview("example-ev.com") is True  # cited via nested element reference
    assert result.owns_ai_overview("unknown.com") is False
    assert result.find("unknown.com") is None


async def test_standard_queue_posts_then_polls_until_ready(serp_fixture):
    calls: list[tuple[str, str]] = []
    polls = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.method, request.url.path))
        auth = base64.b64decode(request.headers["authorization"].split()[1]).decode()
        assert auth == "login@example.com:secret"
        if request.url.path == "/v3/serp/google/organic/task_post":
            body = json.loads(request.content)
            assert body == [
                {
                    "keyword": "ev battery warranty",
                    "location_code": 2840,
                    "language_code": "en",
                    "device": "desktop",
                    "depth": 100,
                    "tag": "0",
                    "stop_crawl_on_match": [
                        {"match_value": "example-ev.com", "match_type": "with_subdomains"}
                    ],
                }
            ]
            return httpx.Response(
                200,
                json=envelope(
                    [
                        {
                            "id": "task-1",
                            "status_code": 20100,
                            "status_message": "Task Created.",
                            "data": {"tag": "0"},
                        }
                    ]
                ),
            )
        polls["n"] += 1
        if polls["n"] == 1:
            return httpx.Response(
                200,
                json=envelope([{"id": "task-1", "status_code": 40602, "status_message": "Task In Queue."}]),
            )
        return httpx.Response(200, json=serp_fixture)

    store = MemoryStore()
    provider, sleeps = make_provider(handler, store=store)
    results = await provider.fetch_serps([QUERY, QUERY])  # duplicates are posted once
    assert results[QUERY].find("example-ev.com").rank_group == 12
    assert [c[1] for c in calls].count("/v3/serp/google/organic/task_post") == 1
    assert calls[-1] == ("GET", "/v3/serp/google/organic/task_get/advanced/task-1")
    assert sleeps == [10]
    assert store.data == {}  # finished tasks are removed from the store


async def test_retry_resumes_pending_task_without_reposting(serp_fixture):
    store = MemoryStore()

    def queued(request):
        if request.url.path.endswith("task_post"):
            return httpx.Response(
                200, json=envelope([{"id": "task-9", "status_code": 20100, "data": {"tag": "0"}}])
            )
        return httpx.Response(200, json=envelope([{"id": "task-9", "status_code": 40601}]))

    provider, _ = make_provider(queued, store=store, max_wait=25)
    with pytest.raises(ProviderError) as exc:
        await provider.fetch_serps([QUERY])
    assert exc.value.retryable
    assert list(store.data.values()) == ["task-9"]

    posted = []

    def ready(request):
        posted.append(request.url.path)
        assert not request.url.path.endswith("task_post"), "retry must not pay for a second task"
        return httpx.Response(200, json=serp_fixture)

    provider2, _ = make_provider(ready, store=store)
    results = await provider2.fetch_serps([QUERY])
    assert results[QUERY].find("example-ev.com").rank_group == 12
    assert posted == ["/v3/serp/google/organic/task_get/advanced/task-9"]


async def test_live_mode_sends_one_task_per_request(serp_fixture):
    seen = []

    def handler(request):
        seen.append(request.url.path)
        assert len(json.loads(request.content)) == 1
        return httpx.Response(200, json=serp_fixture)

    provider, _ = make_provider(handler, mode="live")
    other = SerpQuery("ev charger", 2840, "en", "mobile", 20, "example-ev.com")
    results = await provider.fetch_serps([QUERY, other])
    assert set(results) == {QUERY, other}
    assert seen == ["/v3/serp/google/organic/live/advanced"] * 2


async def test_urgent_requests_use_live_endpoint_in_standard_mode(serp_fixture):
    seen = []

    def handler(request):
        seen.append(request.url.path)
        return httpx.Response(200, json=serp_fixture)

    provider, _ = make_provider(handler, mode="standard", store=MemoryStore())
    results = await provider.fetch_serps([QUERY], urgent=True)
    assert results[QUERY].find("example-ev.com").rank_group == 12
    assert seen == ["/v3/serp/google/organic/live/advanced"]


async def test_queue_timeout_is_pending_not_a_fallback_case():
    def handler(request):
        if request.url.path.endswith("task_post"):
            body = [{"id": "t1", "status_code": 20100, "data": {"tag": "0"}}]
            return httpx.Response(200, json=envelope(body))
        return httpx.Response(200, json=envelope([{"id": "t1", "status_code": 40602}]))

    provider, _ = make_provider(handler, store=MemoryStore(), max_wait=30)
    with pytest.raises(ProviderError) as exc:
        await provider.fetch_serps([QUERY])
    assert exc.value.pending and exc.value.retryable


@pytest.mark.parametrize(
    ("response", "retryable"),
    [
        (httpx.Response(401, json={"status_code": 40100, "status_message": "Not authorized"}), False),
        (httpx.Response(200, json={"status_code": 40200, "status_message": "Payment Required."}), False),
        (httpx.Response(200, json={"status_code": 50000, "status_message": "Internal Error."}), True),
        (httpx.Response(503, text="unavailable"), True),
    ],
)
async def test_error_classification(response, retryable):
    provider, _ = make_provider(lambda request: response)
    with pytest.raises(ProviderError) as exc:
        await provider.fetch_serps([QUERY])
    assert exc.value.retryable is retryable


async def test_keyword_metrics_batches_and_filters():
    requests = []

    def handler(request):
        body = json.loads(request.content)
        requests.append(body)
        items = [
            {
                "keyword": k,
                "search_volume": 1900,
                "competition": "HIGH",
                "competition_index": 87,
                "cpc": 1.23,
                "monthly_searches": [{"year": 2026, "month": 8, "search_volume": 2400}],
            }
            for k in body[0]["keywords"]
        ]
        return httpx.Response(
            200, json=envelope([{"id": "v", "status_code": 20000, "result": items}], cost=0.075)
        )

    provider, _ = make_provider(handler)
    too_long = "x" * 81
    too_many_words = " ".join(["w"] * 11)
    keywords = [f"kw {i}" for i in range(1500)] + [too_long, too_many_words]
    batch = await provider.keyword_metrics(keywords, 2246, "fi")
    assert [len(r[0]["keywords"]) for r in requests] == [1000, 500]
    assert requests[0][0]["location_code"] == 2246 and requests[0][0]["language_code"] == "fi"
    assert len(batch.metrics) == 1500
    assert batch.cost_usd == Decimal("0.150")
    m = batch.metrics[0]
    assert (m.search_volume, m.cpc_usd, m.competition) == (1900, 1.23, 0.87)
    assert m.monthly_searches == [{"year": 2026, "month": 8, "search_volume": 2400}]


def test_parse_search_volume_handles_missing_data():
    m = parse_search_volume_item(
        {
            "keyword": "rare",
            "search_volume": None,
            "competition_index": None,
            "cpc": None,
            "monthly_searches": None,
        }
    )
    assert (m.search_volume, m.competition, m.monthly_searches) == (None, None, None)
