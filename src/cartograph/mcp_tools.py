"""MCP tool definitions for the Cartograph extension.

Exposes codebase analysis, symbol lookup, reading paths, and explanation
as MCP tools discoverable by any MCP client connected to AFS.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .storage import CartographDB, db_path_for_project


def _open_db(project_path: str) -> tuple[CartographDB, str] | tuple[None, str]:
    """Open DB and get project_id. Returns (db, project_id) or (None, error)."""
    root = Path(project_path).resolve()
    db_file = db_path_for_project(root)
    if not db_file.exists():
        return None, f"No index found at {db_file}. Run `carto ingest {root}` first."

    db = CartographDB(db_file)
    db.open()
    pid = db.get_project_id(str(root))
    if not pid:
        db.close()
        return None, f"Project not found in index for {root}."
    return db, pid


def _handle_ingest(arguments: dict[str, Any]) -> dict[str, Any]:
    """Ingest a project directory."""
    from .ingest import ingest

    project_path = arguments.get("path", ".")
    try:
        root = Path(project_path).resolve()
        result = ingest(root, project_name=arguments.get("name"))
        return {
            "project": result.project_name,
            "files_scanned": result.files_scanned,
            "files_parsed": result.files_parsed,
            "files_unchanged": result.files_unchanged,
            "symbols_found": result.symbols_found,
            "references_found": result.references_found,
            "errors": result.errors[:10],
            "files_by_language": result.files_by_language,
        }
    except Exception as e:
        return {"error": str(e)}


def _handle_symbols(arguments: dict[str, Any]) -> dict[str, Any]:
    """Search symbols in an indexed project."""
    project_path = arguments.get("path", ".")
    result = _open_db(project_path)
    if result[0] is None:
        return {"error": result[1]}
    db, pid = result

    try:
        rows = db.search_symbols(
            project_id=pid,
            query=arguments.get("query"),
            kind=arguments.get("kind"),
            limit=arguments.get("limit", 30),
        )
        return {
            "symbols": [
                {
                    "name": r.name,
                    "qualified_name": r.qualified_name,
                    "kind": r.kind,
                    "file": f"{r.file_path}:{r.start_line}",
                    "signature": r.signature,
                    "docstring": r.docstring[:200] if r.docstring else "",
                }
                for r in rows
            ]
        }
    finally:
        db.close()


def _handle_callers(arguments: dict[str, Any]) -> dict[str, Any]:
    """Find callers of a symbol."""
    project_path = arguments.get("path", ".")
    symbol_name = arguments.get("symbol", "")
    if not symbol_name:
        return {"error": "No symbol name provided"}

    result = _open_db(project_path)
    if result[0] is None:
        return {"error": result[1]}
    db, pid = result

    try:
        rows = db.find_callers(pid, symbol_name)
        return {
            "symbol": symbol_name,
            "callers": [
                {
                    "caller": r.source_name,
                    "file": f"{r.file_path}:{r.line}",
                }
                for r in rows
            ],
        }
    finally:
        db.close()


def _handle_path(arguments: dict[str, Any]) -> dict[str, Any]:
    """Generate or list reading paths."""
    from .paths import Strategy, generate_path, list_paths

    project_path = arguments.get("path", ".")
    action = arguments.get("action", "list")

    result = _open_db(project_path)
    if result[0] is None:
        return {"error": result[1]}
    db, pid = result

    try:
        if action == "generate":
            strategy_str = arguments.get("strategy", "complexity-ascending")
            try:
                strategy = Strategy(strategy_str)
            except ValueError:
                return {"error": f"Unknown strategy: {strategy_str}. Use: topological, entry-first, complexity-ascending"}

            path_id = generate_path(db, pid, strategy=strategy, max_steps=arguments.get("max_steps", 100))
            paths = list_paths(db, pid)
            for p in paths:
                if p["id"] == path_id:
                    return {"generated": p}
            return {"path_id": path_id}

        else:
            paths = list_paths(db, pid)
            return {"paths": paths}
    finally:
        db.close()


def _handle_explain(arguments: dict[str, Any]) -> dict[str, Any]:
    """Explain a symbol using an LLM."""
    from .explain import ExplainService

    project_path = arguments.get("path", ".")
    symbol_name = arguments.get("symbol", "")

    result = _open_db(project_path)
    if result[0] is None:
        return {"error": result[1]}
    db, pid = result

    try:
        # Resolve symbol name to ID
        rows = db.search_symbols(pid, query=symbol_name, limit=1)
        if not rows:
            return {"error": f"Symbol '{symbol_name}' not found"}

        root = Path(project_path).resolve()
        svc = ExplainService(
            db=db,
            project_root=root,
            provider=arguments.get("provider", "ollama"),
            model=arguments.get("model"),
        )

        result_data = svc.explain_symbol(
            symbol_id=rows[0].id,
            level=arguments.get("level", "intermediate"),
        )
        return {
            "symbol": rows[0].qualified_name,
            "file": f"{rows[0].file_path}:{rows[0].start_line}",
            **result_data,
        }
    finally:
        db.close()


def _handle_stats(arguments: dict[str, Any]) -> dict[str, Any]:
    """Get project index statistics."""
    project_path = arguments.get("path", ".")

    result = _open_db(project_path)
    if result[0] is None:
        return {"error": result[1]}
    db, pid = result

    try:
        return db.get_project_stats(pid)
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------


def register_mcp_tools() -> list[dict[str, Any]]:
    """Return MCP tool definitions for the Cartograph extension."""
    return [
        {
            "name": "carto.ingest",
            "description": "Ingest a codebase: parse source files, extract symbols and cross-references, store in SQLite index",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                    "name": {
                        "type": "string",
                        "description": "Project name (defaults to directory name)",
                    },
                },
                "required": ["path"],
            },
            "handler": _handle_ingest,
        },
        {
            "name": "carto.symbols",
            "description": "Search symbols (functions, classes, methods) in an indexed codebase",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                    "query": {
                        "type": "string",
                        "description": "Full-text search query for symbol names/docs",
                    },
                    "kind": {
                        "type": "string",
                        "enum": ["function", "class", "method", "variable", "constant"],
                        "description": "Filter by symbol kind",
                    },
                    "limit": {
                        "type": "integer",
                        "description": "Max results (default: 30)",
                        "default": 30,
                    },
                },
                "required": ["path"],
            },
            "handler": _handle_symbols,
        },
        {
            "name": "carto.callers",
            "description": "Find all call sites of a symbol in the indexed codebase",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                    "symbol": {
                        "type": "string",
                        "description": "Symbol name to find callers of",
                    },
                },
                "required": ["path", "symbol"],
            },
            "handler": _handle_callers,
        },
        {
            "name": "carto.path",
            "description": "Generate or list reading paths through a codebase for guided learning",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                    "action": {
                        "type": "string",
                        "enum": ["list", "generate"],
                        "description": "List existing paths or generate a new one",
                        "default": "list",
                    },
                    "strategy": {
                        "type": "string",
                        "enum": ["topological", "entry-first", "complexity-ascending"],
                        "description": "Reading path strategy (for generate action)",
                        "default": "complexity-ascending",
                    },
                    "max_steps": {
                        "type": "integer",
                        "description": "Maximum steps in the path",
                        "default": 100,
                    },
                },
                "required": ["path"],
            },
            "handler": _handle_path,
        },
        {
            "name": "carto.explain",
            "description": "Get an LLM-generated explanation of a code symbol, with caching",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                    "symbol": {
                        "type": "string",
                        "description": "Symbol name to explain",
                    },
                    "level": {
                        "type": "string",
                        "enum": ["beginner", "intermediate", "expert"],
                        "description": "Explanation depth level",
                        "default": "intermediate",
                    },
                    "provider": {
                        "type": "string",
                        "enum": ["ollama", "gemini"],
                        "description": "LLM provider",
                        "default": "ollama",
                    },
                    "model": {
                        "type": "string",
                        "description": "Model name (provider-specific)",
                    },
                },
                "required": ["path", "symbol"],
            },
            "handler": _handle_explain,
        },
        {
            "name": "carto.stats",
            "description": "Get statistics for an indexed codebase: file counts, symbol counts, cross-references",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the project root directory",
                    },
                },
                "required": ["path"],
            },
            "handler": _handle_stats,
        },
    ]
