"""Job runner: claim → dispatch → heartbeat → complete/fail.

Runs up to `concurrency` jobs at once, heartbeats each running job, and on
SIGTERM stops claiming and lets in-flight jobs finish (Fly kill_timeout).
"""

from __future__ import annotations

import asyncio
import logging
import signal
from collections.abc import Awaitable, Callable
from typing import Any

from .config import Settings
from .db import Database, Job
from .providers import ProviderError, SerpProvider
from .rank.handler import PermanentJobError, RankCheckContext, handle_rank_check

log = logging.getLogger(__name__)

Handler = Callable[[Job], Awaitable[dict[str, Any]]]


class Runner:
    def __init__(self, settings: Settings, db: Database, provider: SerpProvider):
        self.settings = settings
        self.db = db
        self.provider = provider
        rank_ctx = RankCheckContext(
            db=db, provider=provider, metrics_max_age_days=settings.keyword_metrics_max_age_days
        )
        self.handlers: dict[str, Handler] = {
            "rank_check": lambda job: handle_rank_check(job, rank_ctx),
        }
        self._stopping = asyncio.Event()
        self._running: set[asyncio.Task[None]] = set()

    def stop(self) -> None:
        if not self._stopping.is_set():
            log.info("stop requested: finishing %d running job(s)", len(self._running))
        self._stopping.set()

    def install_signal_handlers(self) -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, self.stop)

    async def run_forever(self) -> None:
        queues = [q for q in self.settings.queues if q in self.handlers]
        unknown = set(self.settings.queues) - set(queues)
        if unknown:
            log.warning("no handler for queue(s) %s — ignoring", ", ".join(sorted(unknown)))
        log.info("worker %s consuming %s", self.settings.worker_id, ", ".join(queues))
        while not self._stopping.is_set():
            free = self.settings.concurrency - len(self._running)
            claimed = await self.db.claim_jobs(queues, self.settings.worker_id, free) if free > 0 else []
            for job in claimed:
                task = asyncio.create_task(self.process(job))
                self._running.add(task)
                task.add_done_callback(self._running.discard)
            if not claimed:
                try:
                    await asyncio.wait_for(self._stopping.wait(), timeout=self.settings.poll_interval)
                except TimeoutError:
                    pass
        if self._running:
            await asyncio.gather(*self._running, return_exceptions=True)

    async def run_once(self) -> int:
        """Process queued jobs until none are left (tests, one-off runs). Returns jobs processed."""
        queues = [q for q in self.settings.queues if q in self.handlers]
        processed = 0
        while True:
            jobs = await self.db.claim_jobs(queues, self.settings.worker_id, self.settings.concurrency)
            if not jobs:
                return processed
            await asyncio.gather(*(self.process(job) for job in jobs))
            processed += len(jobs)

    async def process(self, job: Job) -> None:
        handler = self.handlers.get(job.queue)
        worker = self.settings.worker_id
        if handler is None:
            await self.db.fail_job(job.id, worker, f"no handler for queue {job.queue}", retryable=False)
            return
        heartbeat = asyncio.create_task(self._heartbeat(job))
        try:
            result = await handler(job)
        except PermanentJobError as exc:
            log.error("job %s (%s) failed permanently: %s", job.id, job.queue, exc)
            await self.db.fail_job(job.id, worker, str(exc), retryable=False)
        except ProviderError as exc:
            log.warning(
                "job %s (%s) provider error (retryable=%s): %s", job.id, job.queue, exc.retryable, exc
            )
            await self.db.fail_job(job.id, worker, f"provider: {exc}", retryable=exc.retryable)
        except Exception as exc:  # noqa: BLE001 — any other failure is retried with backoff
            log.exception("job %s (%s) crashed", job.id, job.queue)
            await self.db.fail_job(job.id, worker, f"{type(exc).__name__}: {exc}", retryable=True)
        else:
            await self.db.complete_job(job.id, worker, result)
        finally:
            heartbeat.cancel()

    async def _heartbeat(self, job: Job) -> None:
        while True:
            await asyncio.sleep(self.settings.heartbeat_interval)
            try:
                if not await self.db.heartbeat(job.id, self.settings.worker_id):
                    log.warning("job %s: lock lost (reclaimed by another worker?)", job.id)
            except Exception:  # noqa: BLE001
                log.exception("job %s: heartbeat failed", job.id)
