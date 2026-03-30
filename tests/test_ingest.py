"""Tests for the ingestion pipeline."""

from pathlib import Path

import pytest

from cartograph.ingest import ingest
from cartograph.storage import CartographDB

FIXTURES = Path(__file__).parent / "fixtures" / "sample_python"


def test_ingest_fixture_project(tmp_path):
    """Should successfully ingest the sample Python fixtures."""
    db_path = tmp_path / "test.sqlite3"
    db = CartographDB(db_path)
    db.open()

    result = ingest(FIXTURES, project_name="sample", db=db)

    assert result.files_parsed > 0
    assert result.symbols_found > 0
    assert result.references_found > 0
    assert not result.errors

    # Verify we can query the results
    pid = db.get_project_id(str(FIXTURES.resolve()))
    assert pid is not None

    stats = db.get_project_stats(pid)
    assert stats["symbol_count"] > 5  # We know the fixture has several symbols

    # Verify specific symbols exist
    symbols = db.search_symbols(pid, query="FileProcessor")
    assert len(symbols) >= 1

    symbols = db.search_symbols(pid, query="validate")
    assert len(symbols) >= 1

    db.close()


def test_ingest_incremental(tmp_path):
    """Second ingest should skip unchanged files."""
    db_path = tmp_path / "test.sqlite3"
    db = CartographDB(db_path)
    db.open()

    result1 = ingest(FIXTURES, project_name="sample", db=db)
    result2 = ingest(FIXTURES, project_name="sample", db=db)

    assert result2.files_unchanged == result1.files_parsed
    assert result2.files_parsed == 0

    db.close()


def test_ingest_not_a_directory(tmp_path):
    """Should raise ValueError for non-directory input."""
    with pytest.raises(ValueError, match="Not a directory"):
        ingest(tmp_path / "nonexistent")
