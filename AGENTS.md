# AGENTS.md — Cartograph

## Context
Cartograph is an AFS extension that ingests codebases, builds symbol graphs via tree-sitter, and generates guided reading paths.

## Protocol
- Database: per-project SQLite at `<project>/.context/cartograph.sqlite3`
- CLI entry: `carto <subcommand>`
- MCP tools: registered via `extension.toml` → `cartograph.mcp_tools.register_mcp_tools`

## Constraints
- No network calls during ingestion (tree-sitter is local)
- LLM calls only in `explain.py`, always cached by content_hash
- Accept approximate cross-references in dynamic languages; mark confidence
