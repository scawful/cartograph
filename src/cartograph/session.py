"""Session management: track progress through reading paths.

Supports "continue where I left off" for zero-friction re-entry.
"""

from __future__ import annotations

import hashlib
import logging
from datetime import datetime, timezone
from typing import Any

from .paths import get_step
from .storage import CartographDB

log = logging.getLogger(__name__)


def create_session(
    db: CartographDB,
    project_id: str,
    path_id: str,
) -> str:
    """Create a new session for walking a reading path. Returns session ID."""
    session_id = hashlib.sha256(
        f"{project_id}:{path_id}:{datetime.now(timezone.utc).isoformat()}".encode()
    ).hexdigest()[:16]

    now = datetime.now(timezone.utc).isoformat()
    db.conn.execute(
        """
        INSERT INTO sessions (id, project_id, path_id, current_step, started_at, last_active, status)
        VALUES (?, ?, ?, 1, ?, ?, 'active')
        """,
        (session_id, project_id, path_id, now, now),
    )
    db.conn.commit()
    return session_id


def get_active_session(db: CartographDB, project_id: str) -> dict | None:
    """Get the most recent active session for a project."""
    row = db.conn.execute(
        """
        SELECT s.id, s.path_id, s.current_step, s.started_at, s.last_active,
               rp.name, rp.strategy,
               (SELECT COUNT(*) FROM path_steps WHERE path_id = s.path_id) as total_steps
        FROM sessions s
        JOIN reading_paths rp ON s.path_id = rp.id
        WHERE s.project_id = ? AND s.status = 'active'
        ORDER BY s.last_active DESC
        LIMIT 1
        """,
        (project_id,),
    ).fetchone()

    if not row:
        return None

    return {
        "session_id": row[0],
        "path_id": row[1],
        "current_step": row[2],
        "started_at": row[3],
        "last_active": row[4],
        "path_name": row[5],
        "strategy": row[6],
        "total_steps": row[7],
    }


def advance_step(db: CartographDB, session_id: str) -> dict | None:
    """Advance to the next step. Returns the new step data or None if path complete."""
    row = db.conn.execute(
        "SELECT path_id, current_step FROM sessions WHERE id = ?",
        (session_id,),
    ).fetchone()
    if not row:
        return None

    path_id, current_step = row
    next_step_num = current_step + 1

    step_data = get_step(db, path_id, next_step_num)
    if step_data is None:
        # Path complete
        db.conn.execute(
            "UPDATE sessions SET status = 'completed', last_active = ? WHERE id = ?",
            (datetime.now(timezone.utc).isoformat(), session_id),
        )
        db.conn.commit()
        return None

    now = datetime.now(timezone.utc).isoformat()
    db.conn.execute(
        "UPDATE sessions SET current_step = ?, last_active = ? WHERE id = ?",
        (next_step_num, now, session_id),
    )
    db.conn.commit()

    return step_data


def get_current_step(db: CartographDB, session_id: str) -> dict | None:
    """Get the current step for a session."""
    row = db.conn.execute(
        "SELECT path_id, current_step FROM sessions WHERE id = ?",
        (session_id,),
    ).fetchone()
    if not row:
        return None

    return get_step(db, row[0], row[1])


def get_progress(db: CartographDB, session_id: str) -> dict:
    """Get progress statistics for a session."""
    row = db.conn.execute(
        """
        SELECT s.current_step, s.started_at, s.last_active, s.status,
               rp.name,
               (SELECT COUNT(*) FROM path_steps WHERE path_id = s.path_id) as total_steps,
               (SELECT SUM(estimated_minutes) FROM path_steps WHERE path_id = s.path_id) as total_minutes,
               (SELECT SUM(estimated_minutes) FROM path_steps
                WHERE path_id = s.path_id AND step_order <= s.current_step) as completed_minutes
        FROM sessions s
        JOIN reading_paths rp ON s.path_id = rp.id
        WHERE s.id = ?
        """,
        (session_id,),
    ).fetchone()

    if not row:
        return {"error": "Session not found"}

    current, started, last_active, status, name, total_steps, total_min, done_min = row
    total_steps = total_steps or 0
    total_min = total_min or 0
    done_min = done_min or 0
    pct = (current / total_steps * 100) if total_steps > 0 else 0

    return {
        "path_name": name,
        "current_step": current,
        "total_steps": total_steps,
        "percent_complete": round(pct, 1),
        "minutes_completed": done_min,
        "minutes_remaining": total_min - done_min,
        "status": status,
        "started_at": started,
        "last_active": last_active,
    }


def list_sessions(db: CartographDB, project_id: str) -> list[dict]:
    """List all sessions for a project."""
    rows = db.conn.execute(
        """
        SELECT s.id, s.current_step, s.status, s.started_at, s.last_active,
               rp.name, rp.strategy,
               (SELECT COUNT(*) FROM path_steps WHERE path_id = s.path_id) as total_steps
        FROM sessions s
        JOIN reading_paths rp ON s.path_id = rp.id
        WHERE s.project_id = ?
        ORDER BY s.last_active DESC
        """,
        (project_id,),
    ).fetchall()

    return [
        {
            "session_id": r[0],
            "current_step": r[1],
            "status": r[2],
            "started_at": r[3],
            "last_active": r[4],
            "path_name": r[5],
            "strategy": r[6],
            "total_steps": r[7],
        }
        for r in rows
    ]
