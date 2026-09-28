from __future__ import annotations

import json
from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def serp_fixture() -> dict:
    return json.loads((FIXTURES / "task_get_advanced.json").read_text())
