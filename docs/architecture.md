# Architecture

## System Overview

Cartograph is three applications that share a single SQLite database per project:

1. **`carto` CLI** (Python) — The indexing engine. Parses source files with tree-sitter, extracts symbols and cross-references, generates reading paths, and provides LLM explanations. This is the only component that writes to the index tables.

2. **Cartograph.app** (SwiftUI) — The primary learning interface. Reads the index database via GRDB.swift, displays syntax-highlighted code, walks reading paths, and provides LLM explanations through an inspector panel. Writes only to `sessions` and `explanations` tables.

3. **carto-canvas** (C++/ImGui) — A debug companion for developers. Provides a query sandbox, raw SQL inspector, cross-reference explorer, and force-directed graph visualizer. Read-only access to the database.

## Data Flow

```
Source Code (.py, .ts, .js)
    │
    ▼
┌─────────────────────────┐
│  tree-sitter parsing    │  parser.py
│  AST → Symbols + Refs   │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│  SQLite + FTS5          │  storage.py
│  Per-project DB         │
│  WAL mode (concurrent)  │
└───────────┬─────────────┘
            │
    ┌───────┼───────┐
    │       │       │
    ▼       ▼       ▼
  CLI    SwiftUI   ImGui
 (r/w)   (r/w*)   (r/o)

* SwiftUI writes only to sessions/explanations
```

## Python Backend

### Module Responsibilities

| Module | Purpose |
|--------|---------|
| `models.py` | Data classes: Symbol, Reference, SourceFile, ParseResult |
| `parser.py` | tree-sitter AST extraction for Python/TypeScript/JavaScript |
| `storage.py` | SQLite schema, CRUD, FTS5 search |
| `ingest.py` | Directory walker, file filter, parse+store pipeline |
| `resolver.py` | Cross-reference resolution with confidence scoring |
| `graph.py` | SymbolGraph (extends AFS KnowledgeGraph ABC) with traversal algorithms |
| `paths.py` | Reading path generation: topological, entry-first, complexity-ascending |
| `session.py` | Session state management, bookmarking, progress tracking |
| `explain.py` | LLM explanation service with content-hash caching |
| `mcp_tools.py` | MCP tool definitions for Claude integration |
| `cli/__init__.py` | argparse CLI entry point |

### Symbol Extraction

The parser uses tree-sitter to walk the AST and extract:
- **Functions/methods**: name, qualified name, signature, docstring, line range
- **Classes**: name, base classes (inheritance references), docstring
- **Variables/constants**: top-level assignments, UPPER_CASE → constant
- **Imports**: module-level import statements as references
- **Call sites**: function calls within function bodies as cross-references

### Reading Path Strategies

1. **complexity-ascending** — Sorts symbols by line count (simplest first). Best for ADHD: early wins build momentum.
2. **topological** — Reverse topological sort of the dependency graph. Leaves first, entry points last. Bottom-up understanding.
3. **entry-first** — BFS from entry points (main, CLI functions, __init__.py exports). Top-down exploration.

## SwiftUI App

### Data Layer

The app uses **GRDB.swift** to read the Python-generated SQLite schema directly. Key design decisions:

- `DatabasePool` enables concurrent reads while the Python CLI writes (WAL mode)
- Record types (`SymbolRecord`, `XrefRecord`, etc.) map to existing table schemas via `FetchableRecord`
- FTS5 search uses GRDB's `FTS5Pattern` for native full-text queries
- `ValueObservation` provides reactive publishers for live UI updates

### View Hierarchy

```
CartographApp
└── ContentView (NavigationSplitView)
    ├── Sidebar
    │   ├── Dashboard
    │   ├── Symbols
    │   ├── Graph
    │   ├── Focus
    │   └── Reading Paths (dynamic)
    ├── Content Column
    │   ├── DashboardView (stats, resume card)
    │   ├── SymbolBrowserView (search + results)
    │   ├── PathWalkerView (step-by-step reading)
    │   ├── GraphView (force-directed visualization)
    │   └── FocusTimerView (activity ring timer)
    └── Detail Column
        └── CodeViewerView (syntax highlighted)
            └── .inspector → ExplainPanelView
```

### LLM Integration

Adapted from the Tether app's LLM service layer:
- `LLMService` protocol with `generateResponse(prompt:context:config:)`
- `GeminiService` — HTTP POST to Gemini API
- `LocalLLMService` — Ollama and LM Studio support
- `LLMFactory` — routes provider selection to service instances
- `IntelligenceSettings` — persists model config in UserDefaults

## ImGui Companion

### Architecture

Follows the Palette project pattern:
- GLFW + OpenGL3 rendering backend
- ImGui docking branch for workspace layout
- Raw sqlite3 C API for read-only database access
- Catppuccin Mocha color theme

### Panels

| Panel | Purpose |
|-------|---------|
| Query Panel | Symbol search with name/kind filtering |
| SQL Inspector | Raw SQL editor with tabular results |
| XRef Explorer | Clickable caller/callee tree navigation |
| Graph Visualizer | Spring-embedder force-directed layout |

## Concurrent Access

SQLite WAL mode (enabled by the Python CLI) handles all concurrency:
- Multiple readers can operate simultaneously
- One writer at a time (the CLI during ingestion)
- Both GUI apps set a 5-second busy timeout for brief lock contention
- No external coordination mechanism needed
