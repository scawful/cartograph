"""Tests for the SymbolGraph."""

from pathlib import Path

import pytest

from cartograph.graph import SymbolGraph
from cartograph.ingest import ingest
from cartograph.storage import CartographDB

FIXTURES = Path(__file__).parent / "fixtures" / "sample_python"


@pytest.fixture
def db_with_data(tmp_path):
    """Create a DB with ingested fixture data."""
    db = CartographDB(tmp_path / "test.sqlite3")
    db.open()
    ingest(FIXTURES, project_name="sample", db=db)
    pid = db.get_project_id(str(FIXTURES.resolve()))
    yield db, pid
    db.close()


def test_graph_loads(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    graph.load_from_db()
    assert graph.node_count > 5
    assert graph.edge_count > 0


def test_graph_statistics(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    stats = graph.get_statistics()
    assert stats["total_nodes"] > 5
    assert "nodes_by_kind" in stats
    assert "function" in stats["nodes_by_kind"]


def test_topological_sort(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    order = graph.topological_sort()
    assert len(order) > 0
    # All node IDs should be present
    graph.load_from_db()
    assert set(order) == set(graph._nodes.keys())


def test_complexity_order(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    order = graph.complexity_order()
    assert len(order) > 0
    # First node should be one of the simplest
    graph.load_from_db()
    first = graph.get_node(order[0])
    assert first is not None
    assert first.properties.get("line_count", 0) <= 10


def test_bfs_from_entries(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    order = graph.bfs_from_entries()
    assert len(order) > 0


def test_get_context_for_prompt(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    context = graph.get_context_for_prompt("validate")
    assert "validate" in context.lower()


def test_get_context_no_match(db_with_data):
    db, pid = db_with_data
    graph = SymbolGraph(db, pid)
    context = graph.get_context_for_prompt("zzz_nonexistent_zzz")
    assert "No symbols found" in context
