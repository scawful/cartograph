"""Reading path generation: guided code-reading sequences through a codebase.

Three strategies:
- topological: leaves → entry points (bottom-up understanding)
- entry-first: BFS from main/CLI → implementations (top-down exploration)
- complexity-ascending: simplest functions first (ADHD-friendly: early wins)
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from enum import Enum

from .graph import SymbolGraph
from .storage import CartographDB

log = logging.getLogger(__name__)


class Strategy(str, Enum):
    TOPOLOGICAL = "topological"
    ENTRY_FIRST = "entry-first"
    COMPLEXITY_ASCENDING = "complexity-ascending"


@dataclass
class PathStep:
    """A single step in a reading path."""

    step_order: int
    symbol_id: str | None
    file_id: str | None
    title: str
    description: str
    estimated_minutes: int


def _estimate_minutes(line_count: int) -> int:
    """Estimate reading time based on line count. ~5 lines/minute for careful reading."""
    return max(1, min(15, line_count // 5))


def generate_path(
    db: CartographDB,
    project_id: str,
    strategy: Strategy = Strategy.COMPLEXITY_ASCENDING,
    name: str | None = None,
    max_steps: int = 200,
    min_lines: int = 2,
    kinds: set[str] | None = None,
) -> str:
    """Generate a reading path and store it in the database.

    Args:
        db: Open database connection.
        project_id: Project to generate path for.
        strategy: Ordering strategy.
        name: Human-readable path name. Auto-generated if None.
        max_steps: Maximum number of steps to generate.
        min_lines: Minimum line count for a symbol to be included.
        kinds: Filter to these symbol kinds. Default: function, class, method.

    Returns:
        The path ID.
    """
    if kinds is None:
        kinds = {"function", "class", "method"}

    graph = SymbolGraph(db, project_id)
    graph.load_from_db()

    # Get ordered node IDs based on strategy
    if strategy == Strategy.TOPOLOGICAL:
        ordered_ids = graph.topological_sort()
    elif strategy == Strategy.ENTRY_FIRST:
        ordered_ids = graph.bfs_from_entries()
    elif strategy == Strategy.COMPLEXITY_ASCENDING:
        ordered_ids = graph.complexity_order()
    else:
        ordered_ids = graph.topological_sort()

    # Filter to meaningful symbols
    steps: list[PathStep] = []
    for node_id in ordered_ids:
        if len(steps) >= max_steps:
            break

        node = graph.get_node(node_id)
        if node is None:
            continue

        # Filter by kind
        if node.node_type not in kinds:
            continue

        # Filter by minimum size
        line_count = node.properties.get("line_count", 0)
        if line_count < min_lines:
            continue

        props = node.properties
        qname = props.get("qualified_name", node.name)
        file_path = props.get("file_path", "")
        sig = props.get("signature", "")

        # Build step title
        title = f"{file_path} > {qname}"
        if sig:
            title += f"  {sig}"

        # Build description
        desc_parts = []
        doc = props.get("docstring", "")
        if doc:
            desc_parts.append(doc[:200])

        callers = graph.get_predecessors(node_id)[:3]
        if callers:
            caller_names = [c.properties.get("qualified_name", c.name) for c in callers]
            desc_parts.append(f"Called by: {', '.join(caller_names)}")

        callees = graph.get_neighbors(node_id)[:3]
        if callees:
            callee_names = [c.properties.get("qualified_name", c.name) for c in callees]
            desc_parts.append(f"Calls: {', '.join(callee_names)}")

        description = "\n".join(desc_parts) if desc_parts else ""

        steps.append(
            PathStep(
                step_order=len(steps) + 1,
                symbol_id=node_id,
                file_id=None,
                title=title,
                description=description,
                estimated_minutes=_estimate_minutes(line_count),
            )
        )

    # Get project name for path naming
    stats = db.get_project_stats(project_id)
    project_name = stats.get("name", "project")

    if name is None:
        name = f"{project_name}-{strategy.value}"

    # Generate path ID
    path_id = hashlib.sha256(f"{project_id}:{name}:{strategy.value}".encode()).hexdigest()[:16]

    # Delete existing path with same ID (regeneration)
    db.conn.execute("DELETE FROM path_steps WHERE path_id = ?", (path_id,))
    db.conn.execute("DELETE FROM reading_paths WHERE id = ?", (path_id,))

    # Store path
    now = datetime.now(timezone.utc).isoformat()
    db.conn.execute(
        "INSERT INTO reading_paths (id, project_id, name, strategy, created_at) VALUES (?, ?, ?, ?, ?)",
        (path_id, project_id, name, strategy.value, now),
    )

    for step in steps:
        db.conn.execute(
            """
            INSERT INTO path_steps (path_id, step_order, symbol_id, file_id, title, description, estimated_minutes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                path_id,
                step.step_order,
                step.symbol_id,
                step.file_id,
                step.title,
                step.description,
                step.estimated_minutes,
            ),
        )

    db.conn.commit()

    total_minutes = sum(s.estimated_minutes for s in steps)
    hours = total_minutes / 60
    log.info("Generated path '%s': %d steps, ~%.1f hours", name, len(steps), hours)

    return path_id


def list_paths(db: CartographDB, project_id: str) -> list[dict]:
    """List all reading paths for a project."""
    rows = db.conn.execute(
        """
        SELECT rp.id, rp.name, rp.strategy, rp.created_at,
               COUNT(ps.id) as step_count,
               SUM(ps.estimated_minutes) as total_minutes
        FROM reading_paths rp
        LEFT JOIN path_steps ps ON rp.id = ps.path_id
        WHERE rp.project_id = ?
        GROUP BY rp.id
        ORDER BY rp.created_at DESC
        """,
        (project_id,),
    ).fetchall()

    return [
        {
            "id": r[0],
            "name": r[1],
            "strategy": r[2],
            "created_at": r[3],
            "step_count": r[4],
            "total_minutes": r[5] or 0,
        }
        for r in rows
    ]


def get_step(db: CartographDB, path_id: str, step_number: int) -> dict | None:
    """Get a specific step from a reading path.

    Returns dict with step info plus symbol source code location.
    """
    row = db.conn.execute(
        """
        SELECT ps.step_order, ps.symbol_id, ps.title, ps.description,
               ps.estimated_minutes,
               s.name, s.qualified_name, s.kind, s.start_line, s.end_line,
               s.signature, s.docstring,
               sf.relative_path
        FROM path_steps ps
        LEFT JOIN symbols s ON ps.symbol_id = s.id
        LEFT JOIN source_files sf ON s.file_id = sf.id
        WHERE ps.path_id = ? AND ps.step_order = ?
        """,
        (path_id, step_number),
    ).fetchone()

    if not row:
        return None

    total = db.conn.execute(
        "SELECT COUNT(*) FROM path_steps WHERE path_id = ?", (path_id,)
    ).fetchone()

    return {
        "step": row[0],
        "total_steps": total[0] if total else 0,
        "symbol_id": row[1],
        "title": row[2],
        "description": row[3],
        "estimated_minutes": row[4],
        "symbol_name": row[5],
        "qualified_name": row[6],
        "kind": row[7],
        "start_line": row[8],
        "end_line": row[9],
        "signature": row[10],
        "docstring": row[11],
        "file_path": row[12],
    }
