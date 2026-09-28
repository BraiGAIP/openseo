"""SERP change detection: compare a keyword's check with its previous check.

Rules (documented for users in docs/ARCHITECTURE.md §8.6):

* Position — at most one event per check, the most significant one wins:
  started/stopped ranking > entered/left top 3 > entered/left top 10 > a jump of at
  least `jump_threshold` places (position_up / position_down).
* url_changed — the ranking URL differs (scheme, "www." and trailing slash ignored).
* feature_gained / feature_lost — SERP features (featured snippet, local pack, AI Overview …).
* ai_overview_cited / ai_overview_uncited — our domain starts / stops being cited in an
  AI Overview that is present in both checks' SERPs or appears with the citation.
* competitor_entered / competitor_left — a domain enters / leaves the organic top 10
  (our own domain and its subdomains excluded).

No events are produced without a previous check, or when one of the two checks is demo
data (provider 'mock') and the other is not — switching providers is not a SERP change.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any
from urllib.parse import urlsplit

from ..providers.base import domain_matches

DEFAULT_JUMP_THRESHOLD = 5


@dataclass(frozen=True)
class Snapshot:
    position: int | None
    url: str | None = None
    serp_features: tuple[str, ...] = ()
    owns_ai_overview: bool | None = None
    top_domains: tuple[str, ...] | None = None
    provider: str = ""

    @classmethod
    def from_row(cls, row: dict[str, Any]) -> Snapshot:
        top = row.get("top_domains")
        return cls(
            position=row.get("position"),
            url=row.get("url"),
            serp_features=tuple(row.get("serp_features") or ()),
            owns_ai_overview=row.get("owns_ai_overview"),
            top_domains=tuple(top) if top is not None else None,
            provider=row.get("provider") or "",
        )


@dataclass(frozen=True)
class Event:
    kind: str
    subject: str = ""
    payload: dict[str, Any] = field(default_factory=dict)


def _url_key(url: str | None) -> str | None:
    if not url:
        return None
    parts = urlsplit(url.strip())
    host = (parts.hostname or "").lower().removeprefix("www.")
    path = parts.path.rstrip("/") or "/"
    return f"{host}{path}" + (f"?{parts.query}" if parts.query else "")


def _position_event(before: int | None, after: int | None, threshold: int) -> Event | None:
    moved = {"from": before, "to": after}
    if before is None and after is None:
        return None
    if before is None:
        return Event("started_ranking", payload=moved)
    if after is None:
        return Event("stopped_ranking", payload=moved)
    for limit, entered, left in ((3, "entered_top3", "left_top3"), (10, "entered_top10", "left_top10")):
        if before > limit >= after:
            return Event(entered, payload=moved)
        if after > limit >= before:
            return Event(left, payload=moved)
    delta = before - after  # positive = moved up
    if abs(delta) >= threshold:
        return Event("position_up" if delta > 0 else "position_down", payload={**moved, "delta": delta})
    return None


def detect_changes(
    previous: Snapshot | None,
    current: Snapshot,
    own_domain: str,
    jump_threshold: int = DEFAULT_JUMP_THRESHOLD,
) -> list[Event]:
    if previous is None or (previous.provider == "mock") != (current.provider == "mock"):
        return []
    events: list[Event] = []

    position = _position_event(previous.position, current.position, jump_threshold)
    if position:
        events.append(position)

    if previous.position is not None and current.position is not None:
        before_url, after_url = _url_key(previous.url), _url_key(current.url)
        if before_url and after_url and before_url != after_url:
            moved = {"from": previous.url, "to": current.url}
            events.append(Event("url_changed", subject=current.url or "", payload=moved))

    before_features = set(previous.serp_features)
    after_features = set(current.serp_features)
    events += [Event("feature_gained", subject=f) for f in sorted(after_features - before_features)]
    events += [Event("feature_lost", subject=f) for f in sorted(before_features - after_features)]

    if "ai_overview" in after_features:
        if current.owns_ai_overview and not previous.owns_ai_overview:
            events.append(Event("ai_overview_cited"))
        elif current.owns_ai_overview is False and previous.owns_ai_overview:
            events.append(Event("ai_overview_uncited"))

    if previous.top_domains is not None and current.top_domains is not None:

        def others(domains: tuple[str, ...]) -> dict[str, int]:
            return {
                d: rank for rank, d in enumerate(domains[:10], start=1) if not domain_matches(d, own_domain)
            }

        before, after = others(previous.top_domains), others(current.top_domains)
        events += [
            Event("competitor_entered", subject=d, payload={"rank": after[d]})
            for d in after
            if d not in before
        ]
        events += [
            Event("competitor_left", subject=d, payload={"previous_rank": before[d]})
            for d in before
            if d not in after
        ]
    return events
