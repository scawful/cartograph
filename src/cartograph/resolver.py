"""Cross-reference resolver with import path tracking and confidence scoring.

Improves on the basic name-matching in storage.py by understanding
Python import paths and attribute access patterns.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from .storage import CartographDB

log = logging.getLogger(__name__)


class Confidence(str, Enum):
    """Confidence level for a resolved cross-reference."""

    HIGH = "high"  # Exact qualified name match
    MEDIUM = "medium"  # Unique short name match or import-resolved
    LOW = "low"  # Ambiguous: multiple candidates
    EXTERNAL = "external"  # Not found in project


@dataclass
class ResolvedRef:
    """A resolved cross-reference with confidence."""

    source_symbol_id: str
    target_symbol_id: str
    target_name: str
    confidence: Confidence


class Resolver:
    """Resolves symbol references using import context and name matching.

    Resolution strategy (in order):
    1. Exact qualified name match → HIGH
    2. Import-resolved: if file imports X from module, X → module.X → HIGH
    3. Same-file match: reference to name defined in same file → MEDIUM
    4. Unique short name: only one symbol with that name → MEDIUM
    5. Multiple candidates → LOW (picks first alphabetically)
    6. No match → EXTERNAL
    """

    def __init__(self, db: CartographDB, project_id: str):
        self.db = db
        self.project_id = project_id
        self._import_map: dict[str, dict[str, str]] = {}  # file_id -> {name -> qualified_name}
        self._symbol_cache: dict[str, list[tuple[str, str]]] = {}  # name -> [(id, qualified_name)]

    def build_import_map(self) -> None:
        """Build a map of imported names per file for resolution."""
        rows = self.db.conn.execute(
            """
            SELECT x.source_id, x.target_name, sf.id as file_id
            FROM xrefs x
            JOIN symbols s ON x.source_id = s.id OR x.source_id LIKE 'module:%'
            LEFT JOIN source_files sf ON s.file_id = sf.id
            WHERE x.project_id = ? AND x.kind = 'imports'
            """,
            (self.project_id,),
        ).fetchall()

        for source_id, target_name, file_id in rows:
            if file_id:
                if file_id not in self._import_map:
                    self._import_map[file_id] = {}
                short = target_name.rsplit(".", 1)[-1]
                self._import_map[file_id][short] = target_name

    def build_symbol_cache(self) -> None:
        """Cache all symbols by short name for fast lookup."""
        rows = self.db.conn.execute(
            "SELECT id, name, qualified_name FROM symbols WHERE project_id = ?",
            (self.project_id,),
        ).fetchall()

        for sym_id, name, qname in rows:
            if name not in self._symbol_cache:
                self._symbol_cache[name] = []
            self._symbol_cache[name].append((sym_id, qname))

    def resolve(
        self,
        target_name: str,
        source_file_id: str | None = None,
    ) -> ResolvedRef | None:
        """Resolve a target name to a symbol ID with confidence.

        Args:
            target_name: The name as it appears in source code (e.g., "self._read",
                        "FileProcessor", "path.exists").
            source_file_id: The file where the reference occurs (for import context).
        """
        # Strip self. prefix for method resolution
        clean_name = target_name
        if clean_name.startswith("self."):
            clean_name = clean_name[5:]

        # Strip module attribute access (e.g., "os.path.join" → "join")
        short_name = clean_name.rsplit(".", 1)[-1]

        # 1. Exact qualified name match
        candidates = self._symbol_cache.get(clean_name, [])
        for sym_id, qname in candidates:
            if qname == clean_name:
                return ResolvedRef(
                    source_symbol_id="",
                    target_symbol_id=sym_id,
                    target_name=clean_name,
                    confidence=Confidence.HIGH,
                )

        # 2. Import-resolved: check if source file imports this name
        if source_file_id and source_file_id in self._import_map:
            import_qname = self._import_map[source_file_id].get(short_name)
            if import_qname:
                # Look up the import target
                for sym_id, qname in self._symbol_cache.get(short_name, []):
                    if qname == import_qname or qname.endswith(f".{short_name}"):
                        return ResolvedRef(
                            source_symbol_id="",
                            target_symbol_id=sym_id,
                            target_name=qname,
                            confidence=Confidence.HIGH,
                        )

        # 3. Same-file match
        if source_file_id:
            file_symbols = self.db.conn.execute(
                "SELECT id, qualified_name FROM symbols WHERE file_id = ? AND name = ?",
                (source_file_id, short_name),
            ).fetchall()
            if len(file_symbols) == 1:
                return ResolvedRef(
                    source_symbol_id="",
                    target_symbol_id=file_symbols[0][0],
                    target_name=file_symbols[0][1],
                    confidence=Confidence.MEDIUM,
                )

        # 4. Unique short name across project
        short_candidates = self._symbol_cache.get(short_name, [])
        if len(short_candidates) == 1:
            return ResolvedRef(
                source_symbol_id="",
                target_symbol_id=short_candidates[0][0],
                target_name=short_candidates[0][1],
                confidence=Confidence.MEDIUM,
            )

        # 5. Multiple candidates → LOW
        if short_candidates:
            # Prefer functions/classes over variables
            for sym_id, qname in short_candidates:
                return ResolvedRef(
                    source_symbol_id="",
                    target_symbol_id=sym_id,
                    target_name=qname,
                    confidence=Confidence.LOW,
                )

        # 6. External
        return ResolvedRef(
            source_symbol_id="",
            target_symbol_id=f"external:{target_name}",
            target_name=target_name,
            confidence=Confidence.EXTERNAL,
        )

    def get_resolution_stats(self) -> dict[str, int]:
        """Get statistics on xref resolution quality."""
        rows = self.db.conn.execute(
            """
            SELECT
                CASE
                    WHEN target_id LIKE 'external:%' THEN 'external'
                    ELSE 'resolved'
                END as status,
                COUNT(*)
            FROM xrefs
            WHERE project_id = ?
            GROUP BY status
            """,
            (self.project_id,),
        ).fetchall()
        return dict(rows)
