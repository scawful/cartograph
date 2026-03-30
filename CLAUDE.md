# CLAUDE.md (Compact)

Purpose: concise Claude-specific routing for Cartograph.

Claude Rules
1. Follow local `AGENTS.md` first when both exist.
2. Keep edits minimal, reversible, and task-scoped.
3. Prefer existing scripts/tools over ad-hoc commands.
4. Validate with `make test` after changes.
5. Never claim verification that was not actually run.
6. Escalate ambiguity or conflicting requirements quickly.

Build & Test
- `make install` — editable install into venv
- `make test` — run pytest
- `make lint` — run ruff
- `make format` — auto-format with ruff

Architecture
- `src/cartograph/parser.py` — tree-sitter AST extraction
- `src/cartograph/models.py` — Symbol, Reference dataclasses
- `src/cartograph/storage.py` — SQLite schema and CRUD
- `src/cartograph/ingest.py` — directory walk + parse pipeline
- `src/cartograph/cli/` — argparse CLI entry point

Response Contract
- What changed
- How it was validated
- Remaining risks or unknowns
