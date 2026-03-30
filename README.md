# Cartograph

A local-first codebase tutorial platform that ingests software projects and generates interactive learning experiences with guided reading paths, syntax-highlighted code viewing, LLM-powered explanations, and spaced repetition.

Built to help developers actively understand codebases rather than passively consuming AI summaries — with ADHD-friendly features like bounded focus sessions, progress tracking, and micro-rewards.

## Architecture

Cartograph is three applications sharing a single SQLite database:

```
┌──────────────────────────┐   ┌──────────────────────┐
│  Cartograph.app (SwiftUI)│   │  carto-canvas (ImGui) │
│  Learning interface      │   │  Debug companion      │
└────────────┬─────────────┘   └──────────┬───────────┘
             │     cartograph.sqlite3      │
             └────────────┬────────────────┘
                          │
                ┌─────────┴─────────┐
                │  carto CLI (Python)│
                │  Indexing engine   │
                └───────────────────┘
```

| Component | Purpose | Tech |
|-----------|---------|------|
| **`carto` CLI** | Ingests codebases, builds symbol graphs, generates reading paths | Python 3.12+, tree-sitter, SQLite |
| **Cartograph.app** | Guided reading, code viewing, explanations, quizzes, focus mode | SwiftUI, GRDB.swift, macOS 14+ |
| **carto-canvas** | Query sandbox, SQL inspector, graph visualizer, xref explorer | C++17, ImGui, GLFW, OpenGL |

## Quick Start

### 1. Install the CLI

```bash
cd cartograph
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
```

### 2. Index a project

```bash
carto ingest /path/to/your/project
```

This parses Python, TypeScript, and JavaScript files via tree-sitter, extracts symbols and cross-references, and stores everything in `<project>/.context/cartograph.sqlite3`.

### 3. Explore

```bash
# Search symbols
carto symbols -q "authenticate"

# Find callers
carto callers authenticate_user

# Find what a function calls
carto callees authenticate_user

# List symbols in a file
carto file src/auth/login.py

# Project statistics
carto stats
```

### 4. Generate a reading path

```bash
# Three strategies available:
carto path generate --strategy complexity-ascending  # simplest first (ADHD-friendly)
carto path generate --strategy topological           # dependencies first (bottom-up)
carto path generate --strategy entry-first           # main/CLI first (top-down)

# List paths
carto path list

# Walk interactively
carto path walk

# Resume where you left off
carto resume
```

### 5. Get explanations

```bash
# Uses Ollama by default (local, free)
carto explain authenticate_user

# Or use Gemini
carto explain authenticate_user --provider gemini --level beginner
```

### 6. Open the GUI

**SwiftUI App:**
```bash
cd gui/swift
xcodegen generate
open Cartograph.xcodeproj
# Build and run, then open your project's .context/cartograph.sqlite3
```

**ImGui Companion:**
```bash
cd gui/imgui
cmake -B build -S . && cmake --build build
./build/carto-canvas /path/to/project/.context/cartograph.sqlite3
```

## CLI Reference

| Command | Description |
|---------|-------------|
| `carto ingest <path>` | Parse and index a codebase |
| `carto symbols [-q query] [-k kind]` | Search symbols (FTS5) |
| `carto callers <symbol>` | Find call sites of a symbol |
| `carto callees <symbol>` | Find what a symbol calls |
| `carto file <path>` | List symbols in a file |
| `carto stats` | Project index statistics |
| `carto graph` | Symbol graph statistics |
| `carto path generate [--strategy S]` | Generate a reading path |
| `carto path list` | List available reading paths |
| `carto path walk` | Interactive guided code reading |
| `carto resume` | Continue last reading session |
| `carto explain <symbol>` | LLM-powered code explanation |

## SwiftUI App Features

- **Symbol Browser** — Full-text search with kind filter across the entire index
- **Code Viewer** — Syntax-highlighted source with line numbers, symbol highlighting, auto-scroll
- **Path Walker** — Step-by-step guided reading with progress tracking
- **Explain Panel** — LLM explanations at beginner/intermediate/expert levels (Ollama or Gemini)
- **Graph View** — Force-directed visualization of the symbol call graph
- **Focus Timer** — Bounded sessions (5-30 min) with daily streak tracking
- **Quick Notes** — Capture thoughts mid-reading without breaking flow
- **Spaced Repetition** — Quiz-based review with SM-2 interval scheduling
- **Micro-rewards** — Confetti and streak messages on step completion

## ImGui Companion Features

- **Query Panel** — Interactive symbol search with kind filter
- **SQL Inspector** — Raw SQL queries against the index database
- **XRef Explorer** — Clickable caller/callee tree navigation
- **Graph Visualizer** — Force-directed spring-embedder with pan/zoom/click

## MCP Integration

Cartograph exposes 6 MCP tools for Claude integration via the AFS extension system:

| Tool | Description |
|------|-------------|
| `carto.ingest` | Index a codebase |
| `carto.symbols` | Search symbols |
| `carto.callers` | Find callers of a symbol |
| `carto.path` | Generate or list reading paths |
| `carto.explain` | Get LLM explanation of a symbol |
| `carto.stats` | Get index statistics |

## Supported Languages

| Language | Status |
|----------|--------|
| Python | Full support |
| TypeScript | Full support |
| JavaScript | Full support |
| Rust, Go, C/C++ | Planned |

## Data Model

Per-project SQLite database at `<project>/.context/cartograph.sqlite3`:

- **projects** — Indexed projects with metadata
- **source_files** — Files with content hashes for incremental re-indexing
- **symbols** — Functions, classes, methods, variables with signatures and docstrings (FTS5 indexed)
- **xrefs** — Cross-references: calls, imports, inherits
- **reading_paths** / **path_steps** — Generated guided reading sequences
- **sessions** — Reading progress with bookmark support
- **explanations** — Cached LLM explanations keyed by content hash

## Development

```bash
# Run tests
make test

# Lint
make lint

# Format
make format
```

## Requirements

- **CLI**: Python 3.12+, tree-sitter
- **SwiftUI App**: macOS 14+, Xcode 15+, XcodeGen
- **ImGui Companion**: C++17 compiler, CMake, GLFW (`brew install glfw`)
- **LLM Explanations**: Ollama (local, default) or Gemini API key

## License

MIT
