"""End-to-end: real PostgreSQL + all migrations, worker running as service_role.

Spins up a throw-away cluster (same approach as tests/db/run.sh), seeds two tenants,
lets pg enqueue rank_check jobs and runs the worker against a DataForSEO HTTP mock.
Skipped when PostgreSQL server binaries are not installed.
"""

from __future__ import annotations

import copy
import glob
import json
import os
import shutil
import socket
import subprocess
import tempfile
from datetime import date
from pathlib import Path

import httpx
import psycopg
import pytest
from psycopg.rows import dict_row

from openseo_workers.config import Settings
from openseo_workers.db import Database, DbPendingTaskStore, Job
from openseo_workers.providers import DataForSEOProvider, MockProvider, build_serp_provider
from openseo_workers.rank.handler import RankCheckContext, handle_rank_check
from openseo_workers.runner import Runner

REPO = Path(__file__).resolve().parents[3]
USER_A = "00000000-0000-0000-0000-0000000000a1"
USER_B = "00000000-0000-0000-0000-0000000000b1"


def _pg_bin() -> Path | None:
    explicit = os.environ.get("PGBIN")
    candidates = [explicit] if explicit else sorted(glob.glob("/usr/lib/postgresql/*/bin"))
    for c in reversed(candidates):
        if c and (Path(c) / "initdb").exists():
            return Path(c)
    found = shutil.which("initdb")
    return Path(found).parent if found else None


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="session")
def pg_dsn():
    bindir = _pg_bin()
    if bindir is None:
        pytest.skip("PostgreSQL server binaries not found")
    # Not under pytest's root-owned temp tree: the postgres user must be able to reach it.
    tmp = Path(tempfile.mkdtemp(prefix="openseo-pg-"))
    run_as: list[str] = []
    if os.geteuid() == 0:  # initdb refuses to run as root
        shutil.chown(tmp, "postgres")
        run_as = ["runuser", "-u", "postgres", "--"]
    port = _free_port()
    data = tmp / "data"
    subprocess.run(
        [*run_as, bindir / "initdb", "-D", data, "-U", "postgres", "-A", "trust", "-E", "UTF8", "--locale=C"],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        [
            *run_as,
            bindir / "pg_ctl",
            "-D",
            data,
            "-l",
            tmp / "log",
            "-w",
            "start",
            "-o",
            f"-p {port} -k {tmp} -c listen_addresses=''",
        ],
        check=True,
        capture_output=True,
    )
    psql = [
        bindir / "psql",
        "-h",
        str(tmp),
        "-p",
        str(port),
        "-U",
        "postgres",
        "-X",
        "-q",
        "-v",
        "ON_ERROR_STOP=1",
    ]
    try:
        subprocess.run([*psql, "-c", "create database openseo_test"], check=True, capture_output=True)
        subprocess.run(
            [
                *psql,
                "-d",
                "openseo_test",
                "-c",
                'alter database openseo_test set search_path = "$user", public, extensions',
            ],
            check=True,
            capture_output=True,
        )
        files = [REPO / "tests/db/supabase_stub.sql", *sorted((REPO / "supabase/migrations").glob("*.sql"))]
        for f in files:
            subprocess.run(
                [*psql, "-d", "openseo_test", "--single-transaction", "-f", f],
                check=True,
                capture_output=True,
            )
        yield f"host={tmp} port={port} dbname=openseo_test user=postgres"
    finally:
        subprocess.run(
            [*run_as, bindir / "pg_ctl", "-D", data, "-m", "immediate", "stop"], capture_output=True
        )
        shutil.rmtree(tmp, ignore_errors=True)


@pytest.fixture
def seeded(pg_dsn):
    """Two tenants tracking the same keyword for the same domain (agency + its client)."""
    with psycopg.connect(pg_dsn, autocommit=True, row_factory=dict_row) as conn:
        conn.execute("""
            truncate public.jobs, public.usage_records, private.provider_cache, private.keyword_metrics,
                     public.keyword_positions, public.keyword_tracking, public.projects,
                     public.organization_members, public.organizations, auth.users cascade
        """)
        conn.execute(
            "insert into auth.users (id, email) values (%s, 'a@agency.test'), (%s, 'b@client.test')",
            (USER_A, USER_B),
        )
        orgs = {
            str(r["created_by"]): r["id"]
            for r in conn.execute("select id, created_by from public.organizations")
        }
        projects = {}
        for user in (USER_A, USER_B):
            projects[user] = conn.execute(
                "insert into public.projects (organization_id, name, domain, root_url) "
                "values (%s, 'EV', 'example-ev.com', 'https://example-ev.com/') returning id",
                (orgs[user],),
            ).fetchone()["id"]
            conn.execute(
                "insert into public.keyword_tracking (project_id, organization_id, keyword, location_code, "
                "language_code) values (%s, %s, 'EV battery warranty', 2840, 'en')",
                (projects[user], orgs[user]),
            )
        conn.execute("set role service_role")
        enqueued = conn.execute("select public.enqueue_due_rank_checks(100) as n").fetchone()["n"]
        conn.execute("reset role")
        assert enqueued == 2
    return {"orgs": orgs, "projects": projects}


class FakeDataForSEO:
    """Minimal DataForSEO v3 HTTP double: standard queue + search volume."""

    def __init__(self, serp_fixture):
        self.serp = serp_fixture
        self.calls: list[str] = []
        self.posted_tasks = 0

    def __call__(self, request: httpx.Request) -> httpx.Response:
        path = request.url.path
        self.calls.append(path)
        if path == "/v3/serp/google/organic/task_post":
            tasks = json.loads(request.content)
            self.posted_tasks += len(tasks)
            return httpx.Response(
                200,
                json={
                    "status_code": 20000,
                    "tasks": [
                        {"id": f"t{i}", "status_code": 20100, "data": {"tag": t["tag"]}}
                        for i, t in enumerate(tasks)
                    ],
                },
            )
        if path.startswith("/v3/serp/google/organic/task_get/advanced/"):
            body = copy.deepcopy(self.serp)
            body["tasks"][0]["id"] = path.rsplit("/", 1)[-1]
            return httpx.Response(200, json=body)
        if path == "/v3/keywords_data/google_ads/search_volume/live":
            keywords = json.loads(request.content)[0]["keywords"]
            return httpx.Response(
                200,
                json={
                    "status_code": 20000,
                    "cost": 0.075,
                    "tasks": [
                        {
                            "id": "v1",
                            "status_code": 20000,
                            "result": [
                                {
                                    "keyword": k.lower(),
                                    "search_volume": 1900,
                                    "competition_index": 87,
                                    "cpc": 1.23,
                                    "monthly_searches": [{"year": 2026, "month": 8, "search_volume": 2400}],
                                }
                                for k in keywords
                            ],
                        }
                    ],
                },
            )
        return httpx.Response(404, json={"status_code": 40400, "status_message": "Not Found."})


async def test_rank_check_end_to_end_with_dataforseo(pg_dsn, seeded, serp_fixture):
    fake = FakeDataForSEO(serp_fixture)
    settings = Settings(database_url=pg_dsn, worker_id="test-worker", concurrency=1, db_role="service_role")
    db = await Database.connect(pg_dsn, role="service_role", max_size=3)
    client = httpx.AsyncClient(base_url="https://api.dataforseo.com", transport=httpx.MockTransport(fake))
    provider = DataForSEOProvider("l", "p", client=client, store=DbPendingTaskStore(db), poll_interval=0)
    try:
        processed = await Runner(settings, db, provider).run_once()
    finally:
        await client.aclose()
        await db.close()
    assert processed == 2

    with psycopg.connect(pg_dsn, row_factory=dict_row) as conn:
        jobs = conn.execute("select status, result from public.jobs order by id").fetchall()
        assert [j["status"] for j in jobs] == ["succeeded", "succeeded"]
        # Same keyword + market + domain on the same day: the second tenant reuses the cached SERP.
        assert fake.posted_tasks == 1
        assert sorted(j["result"]["serps_fetched"] for j in jobs) == [0, 1]

        rows = conn.execute("""
            select p.position, p.url, p.owns_ai_overview, p.provider, p.estimated_traffic, p.serp_features,
                   k.current_position, k.search_volume, k.cpc_usd, k.competition, k.metrics_updated_at
            from public.keyword_positions p join public.keyword_tracking k on k.id = p.keyword_id
        """).fetchall()
        assert len(rows) == 2
        for r in rows:
            assert r["position"] == 12 and r["current_position"] == 12  # snapshot trigger ran
            assert r["url"] == "https://blog.example-ev.com/ev-battery-life"
            assert r["owns_ai_overview"] is True and r["provider"] == "dataforseo"
            assert r["serp_features"] == ["ai_overview", "people_also_ask"]
            assert (r["search_volume"], float(r["cpc_usd"]), float(r["competition"])) == (1900, 1.23, 0.87)
            assert r["metrics_updated_at"] is not None
            assert float(r["estimated_traffic"]) == 19.0  # ctr(12)=0.01 × 1900

        usage = conn.execute("""
            select organization_id::text, metric::text, quantity, provider_cost_usd
            from public.usage_records order by metric, organization_id
        """).fetchall()
        serp = [u for u in usage if u["metric"] == "serp_query"]
        assert len(serp) == 1 and serp[0]["quantity"] == 2  # pages_count from the SERP
        assert float(serp[0]["provider_cost_usd"]) == 0.00105
        # Keyword volume: fetched once, the second tenant hits the shared metrics cache.
        assert fake.calls.count("/v3/keywords_data/google_ads/search_volume/live") == 1
        assert (
            conn.execute(
                "select count(*) as n from private.provider_cache where cache_key like 'dataforseo:pending:%'"
            ).fetchone()["n"]
            == 0
        )


async def test_retried_job_is_idempotent(pg_dsn, seeded):
    db = await Database.connect(pg_dsn, role="service_role", max_size=2)
    ctx = RankCheckContext(db=db, provider=MockProvider(today=date.today()))
    try:
        with psycopg.connect(pg_dsn, row_factory=dict_row) as conn:
            raw = conn.execute(
                "select id, queue, organization_id::text, project_id::text, payload, attempts, max_attempts"
                " from public.jobs order by id limit 1"
            ).fetchone()
        job = Job(
            raw["id"],
            raw["queue"],
            raw["organization_id"],
            raw["project_id"],
            raw["payload"],
            raw["attempts"],
            raw["max_attempts"],
        )
        first = await handle_rank_check(job, ctx)
        second = await handle_rank_check(job, ctx)  # e.g. worker died after writing, before complete_job
    finally:
        await db.close()
    assert first["checked"] == second["checked"] == 1
    assert second["serps_fetched"] == 0 and second["serps_cached"] == 1
    with psycopg.connect(pg_dsn, row_factory=dict_row) as conn:
        assert conn.execute("select count(*) as n from public.keyword_positions").fetchone()["n"] == 1
        assert (
            conn.execute(
                "select count(*) as n from public.usage_records where job_id = %s", (job.id,)
            ).fetchone()["n"]
            == 2
        )  # one serp_query + one keyword_lookup, never doubled


async def test_worker_falls_back_to_mock_without_credentials(pg_dsn, seeded):
    settings = Settings(database_url=pg_dsn, worker_id="mock-worker", concurrency=2)
    assert not settings.has_dataforseo_credentials
    db = await Database.connect(pg_dsn, role=settings.db_role, max_size=3)
    provider = build_serp_provider(settings, store=DbPendingTaskStore(db))
    assert isinstance(provider, MockProvider)
    try:
        assert await Runner(settings, db, provider).run_once() == 2
    finally:
        await db.close()
    with psycopg.connect(pg_dsn, row_factory=dict_row) as conn:
        providers = {r["provider"] for r in conn.execute("select provider from public.keyword_positions")}
        assert providers == {"mock"}  # demo rows are labelled so the UI can flag them
        statuses = {r["status"] for r in conn.execute("select status from public.jobs")}
        assert statuses == {"succeeded"}


async def test_bad_payload_fails_permanently(pg_dsn, seeded):
    with psycopg.connect(pg_dsn, autocommit=True, row_factory=dict_row) as conn:
        conn.execute("update public.jobs set payload = '{\"keyword_ids\": []}'")
    settings = Settings(database_url=pg_dsn, worker_id="w", concurrency=2)
    db = await Database.connect(pg_dsn, role=settings.db_role, max_size=3)
    try:
        await Runner(settings, db, MockProvider()).run_once()
    finally:
        await db.close()
    with psycopg.connect(pg_dsn, row_factory=dict_row) as conn:
        rows = conn.execute("select status, last_error from public.jobs").fetchall()
    assert {r["status"] for r in rows} == {"dead"}
    assert all("no keyword_ids" in r["last_error"] for r in rows)
