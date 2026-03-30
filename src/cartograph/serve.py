"""Lightweight HTTP server for serving source files to remote clients (iOS)."""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from .storage import CartographDB, db_path_for_project


class CartographSourceHandler(BaseHTTPRequestHandler):
    """HTTP handler for serving source files and symbol data."""

    project_root: Path  # set by server factory
    db_path: Path  # set by server factory

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._send_common_headers()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        try:
            if path == "/api/v1/health":
                self._json(200, {"status": "ok", "service": "cartograph-source"})
            elif path == "/api/v1/source":
                rel_path = (params.get("path") or [None])[0]
                if not rel_path:
                    self._json(400, {"error": "Missing 'path' parameter"})
                    return
                self._serve_source(rel_path)
            elif path == "/api/v1/symbols":
                query = (params.get("q") or [None])[0]
                kind = (params.get("kind") or [None])[0]
                limit = int((params.get("limit") or ["50"])[0])
                self._serve_symbols(query, kind, limit)
            elif path == "/api/v1/stats":
                self._serve_stats()
            else:
                self._json(404, {"error": "Not found"})
        except Exception as exc:  # noqa: BLE001
            self._json(500, {"error": "server_error", "detail": str(exc)})

    def _serve_source(self, rel_path: str) -> None:
        """Serve a source file by relative path with path traversal protection."""
        full = (self.project_root / rel_path).resolve()
        if not str(full).startswith(str(self.project_root.resolve())):
            self._json(403, {"error": "Path traversal blocked"})
            return
        if not full.exists():
            self._json(404, {"error": f"File not found: {rel_path}"})
            return
        if not full.is_file():
            self._json(400, {"error": f"Not a file: {rel_path}"})
            return
        try:
            content = full.read_text(encoding="utf-8")
            self._json(200, {"path": rel_path, "content": content, "size": len(content)})
        except Exception as exc:  # noqa: BLE001
            self._json(500, {"error": str(exc)})

    def _serve_symbols(self, query: str | None, kind: str | None, limit: int) -> None:
        """Search symbols in the project index."""
        if not self.db_path.exists():
            self._json(404, {"error": "No index found for this project"})
            return

        with CartographDB(self.db_path) as db:
            pid = db.get_project_id(str(self.project_root))
            if not pid:
                self._json(404, {"error": "Project not indexed"})
                return

            rows = db.search_symbols(project_id=pid, query=query, kind=kind, limit=limit)
            symbols = [
                {
                    "id": r.id,
                    "name": r.name,
                    "qualified_name": r.qualified_name,
                    "kind": r.kind,
                    "file_path": r.file_path,
                    "start_line": r.start_line,
                    "end_line": r.end_line,
                    "signature": r.signature,
                }
                for r in rows
            ]
            self._json(200, {"symbols": symbols, "count": len(symbols)})

    def _serve_stats(self) -> None:
        """Serve project statistics."""
        if not self.db_path.exists():
            self._json(404, {"error": "No index found for this project"})
            return

        with CartographDB(self.db_path) as db:
            pid = db.get_project_id(str(self.project_root))
            if not pid:
                self._json(404, {"error": "Project not indexed"})
                return

            stats = db.get_project_stats(pid)
            self._json(200, stats)

    def _send_common_headers(self) -> None:
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Cache-Control", "no-store")

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=True).encode("utf-8")
        self.send_response(status)
        self._send_common_headers()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def run_server(project_root: Path, host: str = "0.0.0.0", port: int = 11443) -> None:
    """Start the Cartograph source server."""
    project_root = project_root.resolve()
    db_file = db_path_for_project(project_root)

    CartographSourceHandler.project_root = project_root
    CartographSourceHandler.db_path = db_file

    server = ThreadingHTTPServer((host, port), CartographSourceHandler)
    print(f"Cartograph source server listening on http://{host}:{port}")
    print(f"  Project root: {project_root}")
    if db_file.exists():
        print(f"  Index: {db_file}")
    else:
        print(f"  Warning: No index found at {db_file} (source serving still works)")
    print()
    print("Endpoints:")
    print(f"  GET /api/v1/health         - Health check")
    print(f"  GET /api/v1/source?path=... - Fetch source file")
    print(f"  GET /api/v1/symbols?q=...  - Search symbols")
    print(f"  GET /api/v1/stats          - Project statistics")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
