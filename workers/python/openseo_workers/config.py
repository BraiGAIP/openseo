from __future__ import annotations

import os
import socket
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Literal


class ConfigError(RuntimeError):
    """Raised when the worker configuration is invalid."""


def _bool(value: str | None, default: bool = False) -> bool:
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    database_url: str
    queues: tuple[str, ...] = ("rank_check",)
    worker_id: str = field(default_factory=lambda: f"{socket.gethostname()}-{os.getpid()}")
    concurrency: int = 4
    poll_interval: float = 5.0
    heartbeat_interval: float = 30.0
    # Role assumed per transaction (Supabase: the worker connects as `postgres`
    # and drops to `service_role`). Empty = keep the connecting role.
    db_role: str | None = "service_role"

    # "auto" = DataForSEO when credentials exist, otherwise the mock provider.
    serp_provider: Literal["auto", "dataforseo", "mock"] = "auto"
    dataforseo_login: str | None = None
    dataforseo_password: str | None = None
    dataforseo_mode: Literal["standard", "live"] = "standard"
    dataforseo_base_url: str = "https://api.dataforseo.com"
    dataforseo_max_wait: float = 900.0
    dataforseo_poll_interval: float = 10.0
    # Stop crawling the SERP once the tracked domain is found (billed per page crawled).
    dataforseo_stop_on_match: bool = True

    keyword_metrics_max_age_days: int = 30

    @property
    def has_dataforseo_credentials(self) -> bool:
        return bool(self.dataforseo_login and self.dataforseo_password)

    @classmethod
    def from_env(cls, env: Mapping[str, str] | None = None) -> Settings:
        env = os.environ if env is None else env
        database_url = env.get("DATABASE_URL", "")
        if not database_url:
            raise ConfigError("DATABASE_URL is required")

        provider = env.get("SERP_PROVIDER", "auto").strip().lower() or "auto"
        if provider not in {"auto", "dataforseo", "mock"}:
            raise ConfigError(f"SERP_PROVIDER must be auto, dataforseo or mock (got {provider!r})")
        mode = env.get("DATAFORSEO_MODE", "standard").strip().lower() or "standard"
        if mode not in {"standard", "live"}:
            raise ConfigError(f"DATAFORSEO_MODE must be standard or live (got {mode!r})")

        queues = tuple(q.strip() for q in env.get("QUEUES", "rank_check").split(",") if q.strip())
        defaults = cls(database_url=database_url)
        return cls(
            database_url=database_url,
            queues=queues or ("rank_check",),
            worker_id=env.get("WORKER_ID") or defaults.worker_id,
            concurrency=int(env.get("WORKER_CONCURRENCY", defaults.concurrency)),
            poll_interval=float(env.get("POLL_INTERVAL", defaults.poll_interval)),
            heartbeat_interval=float(env.get("HEARTBEAT_INTERVAL", defaults.heartbeat_interval)),
            db_role=(env.get("DB_ROLE", "service_role") or None),
            serp_provider=provider,  # type: ignore[arg-type]
            dataforseo_login=env.get("DATAFORSEO_LOGIN") or None,
            dataforseo_password=env.get("DATAFORSEO_PASSWORD") or None,
            dataforseo_mode=mode,  # type: ignore[arg-type]
            dataforseo_base_url=env.get("DATAFORSEO_BASE_URL", defaults.dataforseo_base_url).rstrip("/"),
            dataforseo_max_wait=float(env.get("DATAFORSEO_MAX_WAIT", defaults.dataforseo_max_wait)),
            dataforseo_poll_interval=float(
                env.get("DATAFORSEO_POLL_INTERVAL", defaults.dataforseo_poll_interval)
            ),
            dataforseo_stop_on_match=_bool(env.get("DATAFORSEO_STOP_ON_MATCH"), True),
            keyword_metrics_max_age_days=int(
                env.get("KEYWORD_METRICS_MAX_AGE_DAYS", defaults.keyword_metrics_max_age_days)
            ),
        )
