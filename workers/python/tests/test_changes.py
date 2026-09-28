from __future__ import annotations

import pytest

from openseo_workers.rank.changes import Snapshot, detect_changes

OWN = "example-ev.fi"


def snap(position, **kw):
    kw.setdefault("provider", "dataforseo")
    return Snapshot(position=position, **kw)


def kinds(events):
    return [(e.kind, e.subject) for e in events]


@pytest.mark.parametrize(
    ("before", "after", "expected"),
    [
        (None, 14, ("started_ranking", {"from": None, "to": 14})),
        (14, None, ("stopped_ranking", {"from": 14, "to": None})),
        (5, 2, ("entered_top3", {"from": 5, "to": 2})),
        (2, 4, ("left_top3", {"from": 2, "to": 4})),
        (15, 9, ("entered_top10", {"from": 15, "to": 9})),
        (8, 12, ("left_top10", {"from": 8, "to": 12})),
        (30, 18, ("position_up", {"from": 30, "to": 18, "delta": 12})),
        (18, 25, ("position_down", {"from": 18, "to": 25, "delta": -7})),
    ],
)
def test_one_position_event_most_significant_first(before, after, expected):
    events = detect_changes(snap(before), snap(after), OWN)
    assert [(e.kind, e.payload) for e in events] == [expected]


def test_small_moves_and_unranked_stay_quiet():
    assert detect_changes(snap(14), snap(12), OWN) == []  # below the 5-place threshold
    assert detect_changes(snap(None), snap(None), OWN) == []
    assert kinds(detect_changes(snap(14), snap(11), OWN, jump_threshold=3)) == [("position_up", "")]


def test_top3_wins_over_top10_and_jump():
    # 15 → 2 crosses top 10 and top 3 and jumps 13 places: report the top-3 entry only
    assert kinds(detect_changes(snap(15), snap(2), OWN)) == [("entered_top3", "")]


def test_url_change_ignores_scheme_www_and_trailing_slash():
    a = snap(4, url="https://www.example-ev.fi/akku/")
    assert detect_changes(a, snap(4, url="http://example-ev.fi/akku"), OWN) == []
    events = detect_changes(a, snap(4, url="https://example-ev.fi/akku-takuu"), OWN)
    assert kinds(events) == [("url_changed", "https://example-ev.fi/akku-takuu")]
    assert events[0].payload == {
        "from": "https://www.example-ev.fi/akku/",
        "to": "https://example-ev.fi/akku-takuu",
    }


def test_serp_features_and_ai_overview_citation():
    before = snap(3, serp_features=("people_also_ask", "video"), owns_ai_overview=None)
    after = snap(3, serp_features=("ai_overview", "people_also_ask"), owns_ai_overview=True)
    assert kinds(detect_changes(before, after, OWN)) == [
        ("feature_gained", "ai_overview"),
        ("feature_lost", "video"),
        ("ai_overview_cited", ""),
    ]
    cited = snap(3, serp_features=("ai_overview",), owns_ai_overview=True)
    dropped = snap(3, serp_features=("ai_overview",), owns_ai_overview=False)
    assert kinds(detect_changes(cited, dropped, OWN)) == [("ai_overview_uncited", "")]
    # AI Overview disappeared entirely: feature_lost says it all
    assert kinds(detect_changes(cited, snap(3), OWN)) == [("feature_lost", "ai_overview")]


def test_competitors_entering_and_leaving_the_top10():
    before = snap(2, top_domains=("wiki.fi", OWN, "shop.fi", "old.fi"))
    after = snap(2, top_domains=("wiki.fi", "blog.example-ev.fi", "shop.fi", "new.fi"))
    events = detect_changes(before, after, OWN)
    assert kinds(events) == [("competitor_entered", "new.fi"), ("competitor_left", "old.fi")]
    assert events[0].payload == {"rank": 4} and events[1].payload == {"previous_rank": 4}


def test_competitors_need_top_domains_on_both_checks():
    assert detect_changes(snap(2, top_domains=None), snap(2, top_domains=("x.fi",)), OWN) == []


def test_no_baseline_or_provider_switch_means_no_events():
    assert detect_changes(None, snap(3), OWN) == []
    assert detect_changes(snap(40, provider="mock"), snap(3, provider="dataforseo"), OWN) == []
    # a real fallback provider is still real data
    assert kinds(detect_changes(snap(40, provider="dataforseo"), snap(3, provider="serper"), OWN)) == [
        ("entered_top3", "")
    ]
