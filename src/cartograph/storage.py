"""SQLite storage layer for Cartograph."""

from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .models import (
    Language,
    Reference,
    ReferenceKind,
    SourceFile,
    Symbol,
    SymbolKind,
)

DEFAULT_DB_FILENAME = "cartograph.sqlite3"

_SCHEMA = """
CREATE TABLE IF NOT EXISTS projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    root_path TEXT NOT NULL UNIQUE,
    indexed_at TEXT,
    file_count INTEGER DEFAULT 0,
    symbol_count INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS source_files (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    relative_path TEXT NOT NULL,
    language TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    size_bytes INTEGER,
    indexed_at TEXT,
    UNIQUE(project_id, relative_path)
);

CREATE TABLE IF NOT EXISTS symbols (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL REFERENCES projects(id),
    file_id TEXT NOT NULL REFERENCES source_files(id),
    name TEXT NOT NULL,
    qualified_name TEXT,
    kind TEXT NOT NULL,
    start_line INTEGER NOT NULL,
    end_line INTEGER NOT NULL,
    signature TEXT,
    docstring TEXT,
    parent_id TEXT REFERENCES symbols(id),
    parent_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_sym_name ON symbols(name);
CREATE INDEX IF NOT EXISTS idx_sym_kind ON symbols(kind);
CREATE INDEX IF NOT EXISTS idx_sym_file ON symbols(file_id);
CREATE INDEX IF NOT EXISTS idx_sym_project ON symbols(project_id);

CREATE TABLE IF NOT EXISTS xrefs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    source_id TEXT NOT NULL,
    target_id TEXT NOT NULL,
    source_name TEXT NOT NULL,
    target_name TEXT NOT NULL,
    kind TEXT NOT NULL,
    line INTEGER,
    UNIQUE(source_id, target_id, kind, line)
);

CREATE INDEX IF NOT EXISTS idx_xref_source ON xrefs(source_id);
CREATE INDEX IF NOT EXISTS idx_xref_target ON xrefs(target_id);
CREATE INDEX IF NOT EXISTS idx_xref_target_name ON xrefs(target_name);
CREATE INDEX IF NOT EXISTS idx_xref_source_name ON xrefs(source_name);

CREATE TABLE IF NOT EXISTS module_deps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id TEXT NOT NULL,
    source_file TEXT NOT NULL REFERENCES source_files(id),
    target_file TEXT NOT NULL REFERENCES source_files(id),
    import_name TEXT,
    UNIQUE(source_file, target_file, import_name)
);

CREATE TABLE IF NOT EXISTS reading_paths (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    name TEXT NOT NULL,
    strategy TEXT NOT NULL,
    created_at TEXT
);

CREATE TABLE IF NOT EXISTS path_steps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path_id TEXT NOT NULL REFERENCES reading_paths(id),
    step_order INTEGER NOT NULL,
    symbol_id TEXT REFERENCES symbols(id),
    file_id TEXT REFERENCES source_files(id),
    title TEXT NOT NULL,
    description TEXT,
    estimated_minutes INTEGER DEFAULT 5,
    UNIQUE(path_id, step_order)
);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    project_id TEXT NOT NULL,
    path_id TEXT REFERENCES reading_paths(id),
    current_step INTEGER DEFAULT 0,
    started_at TEXT,
    last_active TEXT,
    status TEXT DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS explanations (
    id TEXT PRIMARY KEY,
    symbol_id TEXT,
    file_id TEXT,
    content_hash TEXT NOT NULL,
    level TEXT DEFAULT 'intermediate',
    explanation TEXT NOT NULL,
    model_used TEXT,
    generated_at TEXT
);
"""

_FTS_SCHEMA = """
CREATE VIRTUAL TABLE IF NOT EXISTS symbols_fts USING fts5(
    name, qualified_name, docstring, signature,
    content=symbols, content_rowid=rowid
);
"""

_FTS_TRIGGERS = """
CREATE TRIGGER IF NOT EXISTS symbols_fts_insert AFTER INSERT ON symbols BEGIN
    INSERT INTO symbols_fts(rowid, name, qualified_name, docstring, signature)
    VALUES (new.rowid, new.name, new.qualified_name, new.docstring, new.signature);
END;

CREATE TRIGGER IF NOT EXISTS symbols_fts_delete AFTER DELETE ON symbols BEGIN
    INSERT INTO symbols_fts(symbols_fts, rowid, name, qualified_name, docstring, signature)
    VALUES ('delete', old.rowid, old.name, old.qualified_name, old.docstring, old.signature);
END;

CREATE TRIGGER IF NOT EXISTS symbols_fts_update AFTER UPDATE ON symbols BEGIN
    INSERT INTO symbols_fts(symbols_fts, rowid, name, qualified_name, docstring, signature)
    VALUES ('delete', old.rowid, old.name, old.qualified_name, old.docstring, old.signature);
    INSERT INTO symbols_fts(rowid, name, qualified_name, docstring, signature)
    VALUES (new.rowid, new.name, new.qualified_name, new.docstring, new.signature);
END;
"""


def _project_id(root_path: str) -> str:
    return hashlib.sha256(root_path.encode()).hexdigest()[:16]


@dataclass
class SymbolRow:
    """A symbol as returned from the database."""

    id: str
    name: str
    qualified_name: str
    kind: str
    file_path: str
    start_line: int
    end_line: int
    signature: str
    docstring: str
    parent_name: str


@dataclass
class XrefRow:
    """A cross-reference as returned from the database."""

    source_name: str
    target_name: str
    kind: str
    file_path: str
    line: int


class CartographDB:
    """SQLite-backed storage for a Cartograph project index."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._conn: sqlite3.Connection | None = None

    def open(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.db_path))
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.executescript(_SCHEMA)
        self._conn.executescript(_FTS_SCHEMA)
        self._conn.executescript(_FTS_TRIGGERS)
        self._conn.commit()

    def close(self) -> None:
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self) -> CartographDB:
        self.open()
        return self

    def __exit__(self, *exc: Any) -> None:
        self.close()

    @property
    def conn(self) -> sqlite3.Connection:
        if self._conn is None:
            raise RuntimeError("Database not open. Call open() first.")
        return self._conn

    # -----------------------------------------------------------------------
    # Project operations
    # -----------------------------------------------------------------------

    def upsert_project(self, name: str, root_path: str) -> str:
        """Create or update a project entry. Returns project_id."""
        pid = _project_id(root_path)
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            """
            INSERT INTO projects (id, name, root_path, indexed_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET indexed_at = ?
            """,
            (pid, name, root_path, now, now),
        )
        self.conn.commit()
        return pid

    def update_project_counts(self, project_id: str) -> None:
        """Update file and symbol counts for a project."""
        row = self.conn.execute(
            "SELECT COUNT(*) FROM source_files WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        file_count = row[0] if row else 0

        row = self.conn.execute(
            "SELECT COUNT(*) FROM symbols WHERE project_id = ?",
            (project_id,),
        ).fetchone()
        sym_count = row[0] if row else 0

        self.conn.execute(
            "UPDATE projects SET file_count = ?, symbol_count = ? WHERE id = ?",
            (file_count, sym_count, project_id),
        )
        self.conn.commit()

    # -----------------------------------------------------------------------
    # File operations
    # -----------------------------------------------------------------------

    def upsert_file(self, project_id: str, src: SourceFile) -> None:
        """Insert or update a source file."""
        now = datetime.now(timezone.utc).isoformat()
        self.conn.execute(
            """
            INSERT INTO source_files (id, project_id, relative_path, language, content_hash, size_bytes, indexed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET content_hash = ?, size_bytes = ?, indexed_at = ?
            """,
            (
                src.id,
                project_id,
                src.relative_path,
                src.language.value,
                src.content_hash,
                src.size_bytes,
                now,
                src.content_hash,
                src.size_bytes,
                now,
            ),
        )

    def get_file_hash(self, file_id: str) -> str | None:
        """Get the content hash for a file, or None if not indexed."""
        row = self.conn.execute(
            "SELECT content_hash FROM source_files WHERE id = ?", (file_id,)
        ).fetchone()
        return row[0] if row else None

    # -----------------------------------------------------------------------
    # Symbol operations
    # -----------------------------------------------------------------------

    def clear_file_symbols(self, file_id: str) -> None:
        """Remove all symbols and xrefs for a file (before re-indexing)."""
        self.conn.execute(
            "DELETE FROM xrefs WHERE source_id IN (SELECT id FROM symbols WHERE file_id = ?)",
            (file_id,),
        )
        self.conn.execute("DELETE FROM symbols WHERE file_id = ?", (file_id,))

    def insert_symbol(self, project_id: str, file_id: str, sym: Symbol) -> None:
        """Insert a symbol."""
        # Resolve parent_id if parent_name is set
        parent_id = None
        if sym.parent_name:
            row = self.conn.execute(
                "SELECT id FROM symbols WHERE qualified_name = ? AND project_id = ?",
                (sym.parent_name, project_id),
            ).fetchone()
            parent_id = row[0] if row else None

        self.conn.execute(
            """
            INSERT OR REPLACE INTO symbols
            (id, project_id, file_id, name, qualified_name, kind,
             start_line, end_line, signature, docstring, parent_id, parent_name)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                sym.id,
                project_id,
                file_id,
                sym.name,
                sym.qualified_name,
                sym.kind.value,
                sym.start_line,
                sym.end_line,
                sym.signature,
                sym.docstring,
                parent_id,
                sym.parent_name,
            ),
        )

    def insert_xref(self, project_id: str, source_sym_id: str, ref: Reference) -> None:
        """Insert a cross-reference. Resolves target to a symbol ID if possible."""
        # Try to resolve target name to a symbol in this project
        target_id = self._resolve_symbol_id(project_id, ref.target_name)
        if target_id is None:
            target_id = f"external:{ref.target_name}"

        try:
            self.conn.execute(
                """
                INSERT OR IGNORE INTO xrefs
                (project_id, source_id, target_id, source_name, target_name, kind, line)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    project_id,
                    source_sym_id,
                    target_id,
                    ref.source_name,
                    ref.target_name,
                    ref.kind.value,
                    ref.line,
                ),
            )
        except sqlite3.IntegrityError:
            pass  # Duplicate, skip

    def _resolve_symbol_id(self, project_id: str, name: str) -> str | None:
        """Resolve a symbol name to its ID within the project."""
        # Try exact qualified name first
        row = self.conn.execute(
            "SELECT id FROM symbols WHERE qualified_name = ? AND project_id = ?",
            (name, project_id),
        ).fetchone()
        if row:
            return row[0]

        # Try just the short name (last component)
        short_name = name.rsplit(".", 1)[-1]
        rows = self.conn.execute(
            "SELECT id FROM symbols WHERE name = ? AND project_id = ?",
            (short_name, project_id),
        ).fetchall()
        if len(rows) == 1:
            return rows[0][0]

        return None

    # -----------------------------------------------------------------------
    # Query operations
    # -----------------------------------------------------------------------

    def search_symbols(
        self,
        project_id: str,
        query: str | None = None,
        kind: str | None = None,
        limit: int = 50,
    ) -> list[SymbolRow]:
        """Search symbols by name (FTS) and/or kind."""
        if query:
            # Use FTS
            sql = """
                SELECT s.id, s.name, s.qualified_name, s.kind,
                       sf.relative_path, s.start_line, s.end_line,
                       s.signature, s.docstring, s.parent_name
                FROM symbols_fts fts
                JOIN symbols s ON s.rowid = fts.rowid
                JOIN source_files sf ON s.file_id = sf.id
                WHERE symbols_fts MATCH ? AND s.project_id = ?
            """
            params: list[Any] = [query + "*", project_id]
            if kind:
                sql += " AND s.kind = ?"
                params.append(kind)
            sql += " LIMIT ?"
            params.append(limit)
        else:
            sql = """
                SELECT s.id, s.name, s.qualified_name, s.kind,
                       sf.relative_path, s.start_line, s.end_line,
                       s.signature, s.docstring, s.parent_name
                FROM symbols s
                JOIN source_files sf ON s.file_id = sf.id
                WHERE s.project_id = ?
            """
            params = [project_id]
            if kind:
                sql += " AND s.kind = ?"
                params.append(kind)
            sql += " ORDER BY sf.relative_path, s.start_line LIMIT ?"
            params.append(limit)

        rows = self.conn.execute(sql, params).fetchall()
        return [
            SymbolRow(
                id=r[0],
                name=r[1],
                qualified_name=r[2],
                kind=r[3],
                file_path=r[4],
                start_line=r[5],
                end_line=r[6],
                signature=r[7] or "",
                docstring=r[8] or "",
                parent_name=r[9] or "",
            )
            for r in rows
        ]

    def find_callers(self, project_id: str, symbol_name: str) -> list[XrefRow]:
        """Find all symbols that call/reference the given symbol."""
        rows = self.conn.execute(
            """
            SELECT x.source_name, x.target_name, x.kind,
                   sf.relative_path, x.line
            FROM xrefs x
            JOIN symbols s ON x.source_id = s.id
            JOIN source_files sf ON s.file_id = sf.id
            WHERE x.project_id = ?
              AND (x.target_name = ? OR x.target_name LIKE ?)
              AND x.kind = 'calls'
            ORDER BY sf.relative_path, x.line
            """,
            (project_id, symbol_name, f"%.{symbol_name}"),
        ).fetchall()
        return [
            XrefRow(
                source_name=r[0],
                target_name=r[1],
                kind=r[2],
                file_path=r[3],
                line=r[4] or 0,
            )
            for r in rows
        ]

    def find_callees(self, project_id: str, symbol_name: str) -> list[XrefRow]:
        """Find all symbols called by the given symbol."""
        rows = self.conn.execute(
            """
            SELECT x.source_name, x.target_name, x.kind,
                   sf.relative_path, x.line
            FROM xrefs x
            JOIN symbols s ON x.source_id = s.id
            JOIN source_files sf ON s.file_id = sf.id
            WHERE x.project_id = ?
              AND (x.source_name = ? OR x.source_name LIKE ?)
              AND x.kind = 'calls'
            ORDER BY x.line
            """,
            (project_id, symbol_name, f"%.{symbol_name}"),
        ).fetchall()
        return [
            XrefRow(
                source_name=r[0],
                target_name=r[1],
                kind=r[2],
                file_path=r[3],
                line=r[4] or 0,
            )
            for r in rows
        ]

    def get_file_symbols(self, project_id: str, file_path: str) -> list[SymbolRow]:
        """Get all symbols in a file, ordered by line number."""
        rows = self.conn.execute(
            """
            SELECT s.id, s.name, s.qualified_name, s.kind,
                   sf.relative_path, s.start_line, s.end_line,
                   s.signature, s.docstring, s.parent_name
            FROM symbols s
            JOIN source_files sf ON s.file_id = sf.id
            WHERE s.project_id = ? AND sf.relative_path = ?
            ORDER BY s.start_line
            """,
            (project_id, file_path),
        ).fetchall()
        return [
            SymbolRow(
                id=r[0],
                name=r[1],
                qualified_name=r[2],
                kind=r[3],
                file_path=r[4],
                start_line=r[5],
                end_line=r[6],
                signature=r[7] or "",
                docstring=r[8] or "",
                parent_name=r[9] or "",
            )
            for r in rows
        ]

    def get_project_id(self, root_path: str) -> str | None:
        """Get project ID by root path."""
        row = self.conn.execute(
            "SELECT id FROM projects WHERE root_path = ?", (root_path,)
        ).fetchone()
        return row[0] if row else None

    def get_project_stats(self, project_id: str) -> dict[str, Any]:
        """Get summary statistics for a project."""
        row = self.conn.execute(
            "SELECT name, root_path, file_count, symbol_count, indexed_at FROM projects WHERE id = ?",
            (project_id,),
        ).fetchone()
        if not row:
            return {}

        kind_counts = self.conn.execute(
            "SELECT kind, COUNT(*) FROM symbols WHERE project_id = ? GROUP BY kind",
            (project_id,),
        ).fetchall()

        xref_count = self.conn.execute(
            "SELECT COUNT(*) FROM xrefs WHERE project_id = ?", (project_id,)
        ).fetchone()

        return {
            "name": row[0],
            "root_path": row[1],
            "file_count": row[2],
            "symbol_count": row[3],
            "indexed_at": row[4],
            "symbols_by_kind": dict(kind_counts),
            "xref_count": xref_count[0] if xref_count else 0,
        }


def db_path_for_project(project_root: Path) -> Path:
    """Return the canonical DB path for a project."""
    context_dir = project_root / ".context"
    return context_dir / DEFAULT_DB_FILENAME
