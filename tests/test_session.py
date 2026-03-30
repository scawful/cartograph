"""Tests for session management."""

from pathlib import Path

import pytest

from cartograph.ingest import ingest
from cartograph.paths import Strategy, generate_path
from cartograph.session import (
    advance_step,
    create_session,
    get_active_session,
    get_current_step,
    get_progress,
    list_sessions,
)
from cartograph.storage import CartographDB

FIXTURES = Path(__file__).parent / "fixtures" / "sample_python"


@pytest.fixture
def db_with_path(tmp_path):
    db = CartographDB(tmp_path / "test.sqlite3")
    db.open()
    ingest(FIXTURES, project_name="sample", db=db)
    pid = db.get_project_id(str(FIXTURES.resolve()))
    path_id = generate_path(db, pid, strategy=Strategy.COMPLEXITY_ASCENDING)
    yield db, pid, path_id
    db.close()


def test_create_session(db_with_path):
    db, pid, path_id = db_with_path
    session_id = create_session(db, pid, path_id)
    assert session_id is not None

    session = get_active_session(db, pid)
    assert session is not None
    assert session["session_id"] == session_id
    assert session["current_step"] == 1


def test_advance_step(db_with_path):
    db, pid, path_id = db_with_path
    session_id = create_session(db, pid, path_id)

    # First step should be current
    step = get_current_step(db, session_id)
    assert step is not None
    assert step["step"] == 1

    # Advance to step 2
    next_step = advance_step(db, session_id)
    assert next_step is not None
    assert next_step["step"] == 2


def test_progress(db_with_path):
    db, pid, path_id = db_with_path
    session_id = create_session(db, pid, path_id)

    progress = get_progress(db, session_id)
    assert progress["current_step"] == 1
    assert progress["total_steps"] > 0
    assert progress["percent_complete"] > 0
    assert progress["status"] == "active"


def test_list_sessions(db_with_path):
    db, pid, path_id = db_with_path
    create_session(db, pid, path_id)

    sessions = list_sessions(db, pid)
    assert len(sessions) == 1
    assert sessions[0]["status"] == "active"


def test_walk_to_completion(db_with_path):
    db, pid, path_id = db_with_path
    session_id = create_session(db, pid, path_id)

    # Walk all steps
    steps_walked = 0
    while True:
        next_step = advance_step(db, session_id)
        if next_step is None:
            break
        steps_walked += 1

    progress = get_progress(db, session_id)
    assert progress["status"] == "completed"
    assert steps_walked > 0
