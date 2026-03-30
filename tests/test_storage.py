"""Tests for SQLite storage layer."""

from pathlib import Path

import pytest

from cartograph.models import Language, Reference, ReferenceKind, SourceFile, Symbol, SymbolKind
from cartograph.storage import CartographDB


@pytest.fixture
def db(tmp_path):
    """Create a temporary database."""
    db = CartographDB(tmp_path / "test.sqlite3")
    db.open()
    yield db
    db.close()


@pytest.fixture
def project_id(db):
    """Create a test project."""
    return db.upsert_project("test-project", "/tmp/test-project")


def test_create_project(db):
    pid = db.upsert_project("myproject", "/tmp/myproject")
    assert pid is not None
    stats = db.get_project_stats(pid)
    assert stats["name"] == "myproject"


def test_upsert_file(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)
    db.conn.commit()

    stored_hash = db.get_file_hash(src.id)
    assert stored_hash == "abc123"


def test_insert_and_search_symbols(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)

    sym = Symbol(
        name="my_function",
        qualified_name="my_function",
        kind=SymbolKind.FUNCTION,
        file_path="src/main.py",
        start_line=10,
        end_line=20,
        signature="my_function(x, y)",
        docstring="Does something useful.",
    )
    db.insert_symbol(project_id, src.id, sym)
    db.conn.commit()

    results = db.search_symbols(project_id, query="my_func")
    assert len(results) == 1
    assert results[0].name == "my_function"
    assert results[0].signature == "my_function(x, y)"


def test_search_by_kind(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)

    for name, kind in [("func1", SymbolKind.FUNCTION), ("MyClass", SymbolKind.CLASS)]:
        db.insert_symbol(
            project_id,
            src.id,
            Symbol(
                name=name,
                qualified_name=name,
                kind=kind,
                file_path="src/main.py",
                start_line=1,
                end_line=5,
            ),
        )
    db.conn.commit()

    funcs = db.search_symbols(project_id, kind="function")
    assert len(funcs) == 1
    assert funcs[0].name == "func1"

    classes = db.search_symbols(project_id, kind="class")
    assert len(classes) == 1
    assert classes[0].name == "MyClass"


def test_find_callers_and_callees(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)

    caller = Symbol(
        name="caller_fn",
        qualified_name="caller_fn",
        kind=SymbolKind.FUNCTION,
        file_path="src/main.py",
        start_line=1,
        end_line=5,
    )
    callee = Symbol(
        name="callee_fn",
        qualified_name="callee_fn",
        kind=SymbolKind.FUNCTION,
        file_path="src/main.py",
        start_line=10,
        end_line=15,
    )
    db.insert_symbol(project_id, src.id, caller)
    db.insert_symbol(project_id, src.id, callee)

    ref = Reference(
        source_file="src/main.py",
        source_name="caller_fn",
        target_name="callee_fn",
        kind=ReferenceKind.CALLS,
        line=3,
    )
    db.insert_xref(project_id, caller.id, ref)
    db.conn.commit()

    callers = db.find_callers(project_id, "callee_fn")
    assert len(callers) == 1
    assert callers[0].source_name == "caller_fn"

    callees = db.find_callees(project_id, "caller_fn")
    assert len(callees) == 1
    assert callees[0].target_name == "callee_fn"


def test_get_file_symbols(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)

    for name, line in [("first", 1), ("second", 10), ("third", 20)]:
        db.insert_symbol(
            project_id,
            src.id,
            Symbol(
                name=name,
                qualified_name=name,
                kind=SymbolKind.FUNCTION,
                file_path="src/main.py",
                start_line=line,
                end_line=line + 5,
            ),
        )
    db.conn.commit()

    syms = db.get_file_symbols(project_id, "src/main.py")
    assert len(syms) == 3
    assert [s.name for s in syms] == ["first", "second", "third"]


def test_project_stats(db, project_id):
    src = SourceFile(
        relative_path="src/main.py",
        language=Language.PYTHON,
        content_hash="abc123",
        size_bytes=1024,
    )
    db.upsert_file(project_id, src)
    db.insert_symbol(
        project_id,
        src.id,
        Symbol(
            name="f",
            qualified_name="f",
            kind=SymbolKind.FUNCTION,
            file_path="src/main.py",
            start_line=1,
            end_line=5,
        ),
    )
    db.conn.commit()
    db.update_project_counts(project_id)

    stats = db.get_project_stats(project_id)
    assert stats["file_count"] == 1
    assert stats["symbol_count"] == 1
