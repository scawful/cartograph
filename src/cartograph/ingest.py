"""Codebase ingestion pipeline: walk, parse, store."""

from __future__ import annotations

import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .models import LANGUAGE_EXTENSIONS, Language
from .parser import parse_file
from .storage import CartographDB, db_path_for_project

log = logging.getLogger(__name__)

# Directories to always skip
_SKIP_DIRS = {
    ".git",
    ".hg",
    ".svn",
    "__pycache__",
    "node_modules",
    ".venv",
    "venv",
    ".tox",
    ".mypy_cache",
    ".ruff_cache",
    ".pytest_cache",
    "dist",
    "build",
    ".egg-info",
    ".context",  # don't index our own DB directory
}

# Max file size to parse (256 KB)
MAX_FILE_SIZE = 256 * 1024


@dataclass
class IngestResult:
    """Summary of an ingestion run."""

    project_name: str
    root_path: str
    files_scanned: int = 0
    files_parsed: int = 0
    files_skipped: int = 0
    files_unchanged: int = 0
    symbols_found: int = 0
    references_found: int = 0
    errors: list[str] = field(default_factory=list)
    files_by_language: dict[str, int] = field(default_factory=dict)


def _should_skip_dir(name: str) -> bool:
    return name in _SKIP_DIRS or name.startswith(".")


def _find_source_files(root: Path) -> list[Path]:
    """Walk project directory and collect supported source files."""
    files: list[Path] = []
    for child in sorted(root.iterdir()):
        if child.is_dir():
            if _should_skip_dir(child.name):
                continue
            files.extend(_find_source_files(child))
        elif child.is_file():
            if child.suffix.lower() in LANGUAGE_EXTENSIONS and child.stat().st_size <= MAX_FILE_SIZE:
                files.append(child)
    return files


def ingest(
    project_root: Path,
    project_name: str | None = None,
    db: CartographDB | None = None,
    progress_callback: callable | None = None,
) -> IngestResult:
    """Ingest a project: parse all source files and store symbols + references.

    Args:
        project_root: Path to the project root directory.
        project_name: Human-readable name. Defaults to directory name.
        db: Optional pre-opened database. If None, opens one at the canonical path.
        progress_callback: Optional callback(current, total, file_path) for progress.

    Returns:
        IngestResult summary.
    """
    project_root = project_root.resolve()
    if not project_root.is_dir():
        raise ValueError(f"Not a directory: {project_root}")

    name = project_name or project_root.name
    result = IngestResult(project_name=name, root_path=str(project_root))

    # Open or reuse DB
    own_db = db is None
    if own_db:
        db = CartographDB(db_path_for_project(project_root))
        db.open()

    try:
        project_id = db.upsert_project(name, str(project_root))

        # Find all source files
        source_files = _find_source_files(project_root)
        result.files_scanned = len(source_files)

        for i, file_path in enumerate(source_files):
            if progress_callback:
                progress_callback(i + 1, len(source_files), str(file_path.relative_to(project_root)))

            # Parse
            parse_result = parse_file(file_path, project_root)

            if parse_result.errors:
                result.errors.extend(parse_result.errors)
                result.files_skipped += 1
                continue

            src = parse_result.source_file

            # Track language stats
            lang_name = src.language.value
            result.files_by_language[lang_name] = result.files_by_language.get(lang_name, 0) + 1

            # Check if file changed since last index
            existing_hash = db.get_file_hash(src.id)
            if existing_hash == src.content_hash:
                result.files_unchanged += 1
                continue

            # Clear old data for this file and re-index
            db.clear_file_symbols(src.id)
            db.upsert_file(project_id, src)

            # Insert symbols
            for sym in parse_result.symbols:
                db.insert_symbol(project_id, src.id, sym)
                result.symbols_found += 1

            # Insert references (need a second pass to resolve source symbol IDs)
            for ref in parse_result.references:
                source_sym_id = db._resolve_symbol_id(project_id, ref.source_name)
                if source_sym_id is None:
                    source_sym_id = f"module:{src.relative_path}"
                db.insert_xref(project_id, source_sym_id, ref)
                result.references_found += 1

            db.conn.commit()
            result.files_parsed += 1

        # Update project counts
        db.update_project_counts(project_id)

    finally:
        if own_db:
            db.close()

    return result
