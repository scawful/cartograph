"""Tests for reading path generation."""

from pathlib import Path

import pytest

from cartograph.ingest import ingest
from cartograph.paths import Strategy, generate_path, get_step, list_paths
from cartograph.storage import CartographDB

FIXTURES = Path(__file__).parent / "fixtures" / "sample_python"


@pytest.fixture
def db_with_data(tmp_path):
    db = CartographDB(tmp_path / "test.sqlite3")
    db.open()
    ingest(FIXTURES, project_name="sample", db=db)
    pid = db.get_project_id(str(FIXTURES.resolve()))
    yield db, pid
    db.close()


def test_generate_complexity_ascending(db_with_data):
    db, pid = db_with_data
    path_id = generate_path(db, pid, strategy=Strategy.COMPLEXITY_ASCENDING)
    assert path_id is not None

    paths = list_paths(db, pid)
    assert len(paths) == 1
    assert paths[0]["step_count"] > 0
    assert paths[0]["strategy"] == "complexity-ascending"


def test_generate_topological(db_with_data):
    db, pid = db_with_data
    path_id = generate_path(db, pid, strategy=Strategy.TOPOLOGICAL)
    paths = list_paths(db, pid)
    assert any(p["strategy"] == "topological" for p in paths)


def test_generate_entry_first(db_with_data):
    db, pid = db_with_data
    path_id = generate_path(db, pid, strategy=Strategy.ENTRY_FIRST)
    paths = list_paths(db, pid)
    assert any(p["strategy"] == "entry-first" for p in paths)


def test_get_step(db_with_data):
    db, pid = db_with_data
    path_id = generate_path(db, pid, strategy=Strategy.COMPLEXITY_ASCENDING)

    step = get_step(db, path_id, 1)
    assert step is not None
    assert step["step"] == 1
    assert step["total_steps"] > 0
    assert step["title"] is not None


def test_regenerate_replaces_old(db_with_data):
    db, pid = db_with_data
    path_id1 = generate_path(db, pid, strategy=Strategy.COMPLEXITY_ASCENDING)
    path_id2 = generate_path(db, pid, strategy=Strategy.COMPLEXITY_ASCENDING)
    # Same strategy + project → same path ID (regenerated)
    assert path_id1 == path_id2
    # Should still have exactly 1 path
    paths = list_paths(db, pid)
    complexity_paths = [p for p in paths if p["strategy"] == "complexity-ascending"]
    assert len(complexity_paths) == 1
