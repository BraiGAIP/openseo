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


KD_PATH = "/v3/dataforseo_labs/google/bulk_keyword_difficulty/live"
VOLUME_PATH = "/v3/keywords_data/google_ads/search_volume/live"


def volume_and_difficulty_handler(requests, *, kd_response=None):
    def handler(request):
        body = json.loads(request.content)
        requests.append((request.url.path, body))
        keywords = body[0]["keywords"]
        if request.url.path == KD_PATH:
            if kd_response is not None:
                return kd_response
            items = [{"se_type": "google", "keyword": k, "keyword_difficulty": 42} for k in keywords]
            result = [{"se_type": "google", "items_count": len(items), "items": items}]
            return httpx.Response(
                200, json=envelope([{"id": "d", "status_code": 20000, "result": result}], 0.02)
            )
        items = [
            {
                "keyword": k,
                "search_volume": 1900,
                "competition": "HIGH",
                "competition_index": 87,
                "cpc": 1.23,
                "monthly_searches": [{"year": 2026, "month": 8, "search_volume": 2400}],
            }
            for k in keywords
        ]
        return httpx.Response(
            200, json=envelope([{"id": "v", "status_code": 20000, "result": items}], cost=0.075)
        )

    return handler


async def test_keyword_metrics_batches_and_filters():
    requests = []
    provider, _ = make_provider(volume_and_difficulty_handler(requests))
    too_long = "x" * 81
    too_many_words = " ".join(["w"] * 11)
    keywords = [f"kw {i}" for i in range(1500)] + [too_long, too_many_words]
    batch = await provider.keyword_metrics(keywords, 2246, "fi")
    volume = [b for path, b in requests if path == VOLUME_PATH]
    difficulty = [b for path, b in requests if path == KD_PATH]
    assert [len(b[0]["keywords"]) for b in volume] == [1000, 500]
    assert [len(b[0]["keywords"]) for b in difficulty] == [1000, 500]
    assert volume[0][0]["location_code"] == 2246 and volume[0][0]["language_code"] == "fi"
    assert difficulty[0][0] == {
        "keywords": difficulty[0][0]["keywords"],
        "location_code": 2246,
        "language_code": "fi",
    }
    assert len(batch.metrics) == 1500
    assert batch.cost_usd == Decimal("0.190")  # 2 × 0.075 volume + 2 × 0.02 difficulty
    m = batch.metrics[0]
    assert (m.search_volume, m.cpc_usd, m.competition, m.keyword_difficulty) == (1900, 1.23, 0.87, 42)
    assert m.monthly_searches == [{"year": 2026, "month": 8, "search_volume": 2400}]


async def test_keyword_difficulty_is_optional_when_labs_is_unavailable():
    requests = []
    forbidden = httpx.Response(200, json={"status_code": 40204, "status_message": "Access denied."})
    provider, _ = make_provider(volume_and_difficulty_handler(requests, kd_response=forbidden))
    batch = await provider.keyword_metrics(["akku"], 2246, "fi")
    assert batch.metrics[0].search_volume == 1900 and batch.metrics[0].keyword_difficulty is None


async def test_keyword_difficulty_outage_retries_the_whole_refresh():
    requests = []
    down = httpx.Response(503, text="unavailable")
    provider, _ = make_provider(volume_and_difficulty_handler(requests, kd_response=down))
    with pytest.raises(ProviderError) as exc:
        await provider.keyword_metrics(["akku"], 2246, "fi")
    assert exc.value.retryable


async def test_keyword_difficulty_can_be_switched_off():
    requests = []
    client = httpx.AsyncClient(
        base_url="https://api.dataforseo.com",
        transport=httpx.MockTransport(volume_and_difficulty_handler(requests)),
    )
    provider = DataForSEOProvider("l", "p", client=client, keyword_difficulty=False)
    await provider.keyword_metrics(["akku"], 2246, "fi")
    assert [path for path, _ in requests] == [VOLUME_PATH]


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
