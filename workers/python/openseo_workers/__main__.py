"""Entry point: `python -m openseo_workers [--queues rank_check] [--once]`."""

from __future__ import annotations

import argparse
import asyncio
import dataclasses
import logging
import os
import sys

from .config import ConfigError, Settings
from .db import Database, DbPendingTaskStore
from .providers import build_serp_provider
from .runner import Runner


async def _main(settings: Settings, once: bool) -> int:
    db = await Database.connect(
        settings.database_url, role=settings.db_role, max_size=max(2, settings.concurrency + 1)
    )
    provider = build_serp_provider(settings, store=DbPendingTaskStore(db))
    runner = Runner(settings, db, provider)
    try:
        if once:
            processed = await runner.run_once()
            logging.getLogger(__name__).info("processed %d job(s)", processed)
        else:
            runner.install_signal_handlers()
            await runner.run_forever()
    finally:
        await provider.aclose()
        await db.close()
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="openseo_workers")
    parser.add_argument("--queues", help="comma-separated queues (overrides QUEUES)")
    parser.add_argument("--once", action="store_true", help="drain the queue once and exit")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )
    try:
        settings = Settings.from_env()
    except ConfigError as exc:
        logging.getLogger(__name__).error("configuration error: %s", exc)
        return 2
    if args.queues:
        settings = dataclasses.replace(
            settings, queues=tuple(q.strip() for q in args.queues.split(",") if q.strip())
        )
    return asyncio.run(_main(settings, args.once))


if __name__ == "__main__":
    raise SystemExit(main())
