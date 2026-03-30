"""Tests for the tree-sitter parser."""

from pathlib import Path

from cartograph.models import ReferenceKind, SymbolKind
from cartograph.parser import parse_file

FIXTURES = Path(__file__).parent / "fixtures" / "sample_python"


def test_parse_python_functions():
    """Should extract top-level functions."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    names = {s.name for s in result.symbols}
    assert "validate" in names
    assert "run" in names


def test_parse_python_class():
    """Should extract classes and methods."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    sym_map = {s.name: s for s in result.symbols}

    assert "FileProcessor" in sym_map
    fp = sym_map["FileProcessor"]
    assert fp.kind == SymbolKind.CLASS

    assert "process" in sym_map
    proc = sym_map["process"]
    assert proc.kind == SymbolKind.METHOD
    assert proc.parent_name == "FileProcessor"


def test_parse_python_constants():
    """Should extract top-level constants."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    names = {s.name for s in result.symbols}
    assert "MAX_SIZE" in names


def test_parse_python_docstrings():
    """Should extract docstrings."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    sym_map = {s.name: s for s in result.symbols}

    assert "FileProcessor" in sym_map
    assert "Processes files" in sym_map["FileProcessor"].docstring

    assert "validate" in sym_map
    assert "Validate a file" in sym_map["validate"].docstring


def test_parse_python_signatures():
    """Should extract function signatures."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    sym_map = {s.name: s for s in result.symbols}

    assert "validate" in sym_map
    sig = sym_map["validate"].signature
    assert "path" in sig


def test_parse_python_call_references():
    """Should extract function call references."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    call_refs = [r for r in result.references if r.kind == ReferenceKind.CALLS]
    call_targets = {r.target_name for r in call_refs}

    # run() calls FileProcessor(), validate(), processor.process(), print()
    assert "FileProcessor" in call_targets
    assert "validate" in call_targets


def test_parse_python_import_references():
    """Should extract import references."""
    result = parse_file(FIXTURES / "main.py", FIXTURES)
    import_refs = [r for r in result.references if r.kind == ReferenceKind.IMPORTS]
    assert len(import_refs) > 0

    targets = {r.target_name for r in import_refs}
    assert "os" in targets


def test_parse_python_inheritance():
    """Cross-file imports should have references."""
    result = parse_file(FIXTURES / "utils.py", FIXTURES)
    import_refs = [r for r in result.references if r.kind == ReferenceKind.IMPORTS]
    assert len(import_refs) > 0


def test_parse_no_errors():
    """Parsing fixture files should produce no errors."""
    for f in FIXTURES.glob("*.py"):
        result = parse_file(f, FIXTURES)
        assert result.errors == [], f"Errors in {f.name}: {result.errors}"


def test_parse_unsupported_extension(tmp_path):
    """Should return error for unsupported extension."""
    f = tmp_path / "test.rs"
    f.write_text("fn main() {}")
    result = parse_file(f, tmp_path)
    assert len(result.errors) > 0
