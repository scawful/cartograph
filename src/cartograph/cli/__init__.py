"""Cartograph CLI: carto <subcommand>."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _cmd_ingest(args: argparse.Namespace) -> None:
    """Ingest a project directory."""
    from ..ingest import ingest
    from ..storage import db_path_for_project

    project_root = Path(args.path).resolve()
    if not project_root.is_dir():
        print(f"Error: {project_root} is not a directory", file=sys.stderr)
        sys.exit(1)

    print(f"Cartograph: Ingesting {project_root}")

    def progress(current: int, total: int, file_path: str) -> None:
        bar_len = 40
        filled = int(bar_len * current / total) if total > 0 else 0
        bar = "=" * filled + "-" * (bar_len - filled)
        print(f"\r  Parsing... [{bar}] {current}/{total}", end="", flush=True)

    result = ingest(
        project_root=project_root,
        project_name=args.name,
        progress_callback=progress,
    )

    print()  # newline after progress bar

    # Print language breakdown
    lang_parts = []
    for lang, count in sorted(result.files_by_language.items()):
        lang_parts.append(f"{count} {lang}")
    files_desc = ", ".join(lang_parts) if lang_parts else "0"

    print(f"  Scanned: {result.files_scanned} source files ({files_desc})")
    print(f"  Parsed: {result.files_parsed} files ({result.files_unchanged} unchanged)")
    print(f"  Symbols: {result.symbols_found} | Cross-refs: {result.references_found}")

    if result.errors:
        print(f"  Errors: {len(result.errors)}")
        for err in result.errors[:5]:
            print(f"    - {err}")

    print(f"  Stored to {db_path_for_project(project_root).relative_to(project_root)}")


def _cmd_symbols(args: argparse.Namespace) -> None:
    """Search and list symbols."""
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        rows = db.search_symbols(
            project_id=pid,
            query=args.query,
            kind=args.kind,
            limit=args.limit,
        )

        if not rows:
            print("No symbols found.")
            return

        for r in rows:
            sig = f"  {r.signature}" if r.signature else ""
            kind_tag = f"[{r.kind}]"
            print(f"  {r.file_path}:{r.start_line:<6} {kind_tag:<12} {r.qualified_name}{sig}")


def _cmd_callers(args: argparse.Namespace) -> None:
    """Find callers of a symbol."""
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        rows = db.find_callers(pid, args.symbol)
        if not rows:
            print(f"No callers found for '{args.symbol}'.")
            return

        print(f"Callers of {args.symbol}:")
        for r in rows:
            print(f"  {r.file_path}:{r.line:<6} {r.source_name}")


def _cmd_callees(args: argparse.Namespace) -> None:
    """Find what a symbol calls."""
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        rows = db.find_callees(pid, args.symbol)
        if not rows:
            print(f"No callees found for '{args.symbol}'.")
            return

        print(f"Called by {args.symbol}:")
        for r in rows:
            print(f"  {r.file_path}:{r.line:<6} {r.target_name}")


def _cmd_file(args: argparse.Namespace) -> None:
    """List symbols in a specific file."""
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        rows = db.get_file_symbols(pid, args.file)
        if not rows:
            print(f"No symbols found in '{args.file}'.")
            return

        print(f"Symbols in {args.file}:")
        for r in rows:
            indent = "    " if r.parent_name else "  "
            kind_tag = f"[{r.kind}]"
            sig = f"  {r.signature}" if r.signature else ""
            print(f"{indent}{r.start_line:<6} {kind_tag:<12} {r.name}{sig}")


def _cmd_stats(args: argparse.Namespace) -> None:
    """Show project statistics."""
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        stats = db.get_project_stats(pid)
        print(f"Project: {stats['name']}")
        print(f"  Root: {stats['root_path']}")
        print(f"  Files: {stats['file_count']}")
        print(f"  Symbols: {stats['symbol_count']}")
        print(f"  Cross-refs: {stats['xref_count']}")
        print(f"  Indexed at: {stats['indexed_at']}")
        if stats.get("symbols_by_kind"):
            print("  By kind:")
            for kind, count in sorted(stats["symbols_by_kind"].items()):
                print(f"    {kind}: {count}")


def _cmd_path_generate(args: argparse.Namespace) -> None:
    """Generate a reading path."""
    from ..paths import Strategy, generate_path, list_paths
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    try:
        strategy = Strategy(args.strategy)
    except ValueError:
        print(f"Error: Unknown strategy '{args.strategy}'. Use: topological, entry-first, complexity-ascending", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        path_id = generate_path(db, pid, strategy=strategy, max_steps=args.max_steps)
        paths = list_paths(db, pid)
        for p in paths:
            if p["id"] == path_id:
                total_min = p["total_minutes"]
                hours = total_min / 60
                print(f"Generated: \"{p['name']}\" ({p['step_count']} steps, ~{hours:.1f} hrs)")
                return


def _cmd_path_list(args: argparse.Namespace) -> None:
    """List available reading paths."""
    from ..paths import list_paths
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        paths = list_paths(db, pid)
        if not paths:
            print("No reading paths found. Run `carto path generate` first.")
            return

        for p in paths:
            hours = (p["total_minutes"] or 0) / 60
            print(f"  {p['name']:<40} {p['step_count']:>4} steps  ~{hours:.1f}h  [{p['strategy']}]")


def _cmd_path_walk(args: argparse.Namespace) -> None:
    """Interactive reading path walker."""
    from ..paths import get_step, list_paths
    from ..session import advance_step, create_session, get_active_session, get_current_step, get_progress
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        # Get or create session
        session = get_active_session(db, pid)
        if session is None:
            # Need a path first
            paths = list_paths(db, pid)
            if not paths:
                print("No reading paths found. Run `carto path generate` first.")
                return
            path_id = paths[0]["id"]
            session_id = create_session(db, pid, path_id)
            session = get_active_session(db, pid)
        else:
            session_id = session["session_id"]

        # Interactive loop
        step_data = get_current_step(db, session_id)
        while step_data:
            _display_step(step_data, project_root)

            # Prompt
            try:
                choice = input("\n  [n]ext  [s]kip  [q]uit: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                choice = "q"

            if choice in ("q", "quit"):
                progress = get_progress(db, session_id)
                print(f"\n  Session saved at step {progress['current_step']}/{progress['total_steps']} ({progress['percent_complete']}%)")
                print(f"  Run `carto path walk` to continue.")
                break
            elif choice in ("n", "next", "s", "skip", ""):
                step_data = advance_step(db, session_id)
                if step_data is None:
                    print("\n  Path complete! You've read through the entire path.")
                    break
            else:
                print(f"  Unknown command: {choice}")


def _display_step(step_data: dict, project_root: Path) -> None:
    """Display a single reading path step."""
    step_num = step_data["step"]
    total = step_data["total_steps"]
    title = step_data["title"]
    kind = step_data.get("kind", "symbol")
    est = step_data.get("estimated_minutes", 5)

    # Progress bar
    pct = step_num / total if total > 0 else 0
    bar_len = 30
    filled = int(bar_len * pct)
    bar = "=" * filled + "-" * (bar_len - filled)

    print(f"\n  Step {step_num}/{total} [{bar}] ~{est}min")
    print(f"  {'─' * 60}")
    print(f"  {title}")

    # Show source code snippet
    file_path = step_data.get("file_path")
    start = step_data.get("start_line")
    end = step_data.get("end_line")
    if file_path and start and end:
        source_path = project_root / file_path
        if source_path.exists():
            try:
                lines = source_path.read_text().splitlines()
                # Show up to 30 lines
                show_start = start - 1
                show_end = min(end, start + 29)
                print()
                for i in range(show_start, show_end):
                    if i < len(lines):
                        print(f"  {i + 1:>4} | {lines[i]}")
                if end > start + 30:
                    print(f"  ... ({end - start - 30} more lines)")
            except OSError:
                pass

    # Show description/context
    desc = step_data.get("description", "")
    if desc:
        print(f"\n  {desc}")


def _cmd_resume(args: argparse.Namespace) -> None:
    """Resume the most recent reading session."""
    # Delegate to path walk
    args.func = _cmd_path_walk
    _cmd_path_walk(args)


def _cmd_explain(args: argparse.Namespace) -> None:
    """Get an LLM explanation of a symbol."""
    from ..explain import ExplainService
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        # Find the symbol
        rows = db.search_symbols(pid, query=args.symbol, limit=1)
        if not rows:
            print(f"Symbol '{args.symbol}' not found.")
            return

        sym = rows[0]
        print(f"Explaining: {sym.qualified_name} ({sym.kind}) in {sym.file_path}:{sym.start_line}")
        print()

        svc = ExplainService(
            db=db,
            project_root=project_root,
            provider=args.provider,
            model=args.model,
        )

        result = svc.explain_symbol(
            symbol_id=sym.id,
            level=args.level,
        )

        if result.get("cached"):
            print("[cached]")
        print(result["explanation"])


def _cmd_serve(args: argparse.Namespace) -> None:
    """Start the source server for remote clients."""
    from ..serve import run_server

    project_root = Path(args.path).resolve()
    if not project_root.is_dir():
        print(f"Error: {project_root} is not a directory", file=sys.stderr)
        sys.exit(1)

    run_server(project_root, host=args.host, port=args.port)


def _cmd_graph_stats(args: argparse.Namespace) -> None:
    """Show symbol graph statistics."""
    from ..graph import SymbolGraph
    from ..storage import CartographDB, db_path_for_project

    project_root = Path(args.path).resolve()
    db_file = db_path_for_project(project_root)
    if not db_file.exists():
        print(f"Error: No index found. Run `carto ingest {project_root}` first.", file=sys.stderr)
        sys.exit(1)

    with CartographDB(db_file) as db:
        pid = db.get_project_id(str(project_root))
        if not pid:
            print("Error: Project not found in index.", file=sys.stderr)
            sys.exit(1)

        graph = SymbolGraph(db, pid)
        stats = graph.get_statistics()

        print(f"Symbol Graph:")
        print(f"  Nodes: {stats['total_nodes']}")
        print(f"  Edges: {stats['total_edges']}")
        print(f"  Entry points: {stats['entry_points']}")
        print(f"  Leaf nodes: {stats['leaf_nodes']}")
        if stats.get("nodes_by_kind"):
            print("  Nodes by kind:")
            for kind, count in sorted(stats["nodes_by_kind"].items()):
                print(f"    {kind}: {count}")
        if stats.get("edges_by_type"):
            print("  Edges by type:")
            for etype, count in sorted(stats["edges_by_type"].items()):
                print(f"    {etype}: {count}")


def main(argv: list[str] | None = None) -> None:
    """Main CLI entry point."""
    parser = argparse.ArgumentParser(
        prog="carto",
        description="Cartograph: map your codebase for learning",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    # ingest
    p_ingest = subparsers.add_parser("ingest", help="Ingest a project directory")
    p_ingest.add_argument("path", nargs="?", default=".", help="Project root (default: .)")
    p_ingest.add_argument("--name", help="Project name (default: directory name)")
    p_ingest.set_defaults(func=_cmd_ingest)

    # symbols
    p_symbols = subparsers.add_parser("symbols", help="Search symbols")
    p_symbols.add_argument("--query", "-q", help="Search query (FTS)")
    p_symbols.add_argument("--kind", "-k", help="Filter by kind (function, class, method, ...)")
    p_symbols.add_argument("--limit", "-n", type=int, default=50, help="Max results (default: 50)")
    p_symbols.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_symbols.set_defaults(func=_cmd_symbols)

    # callers
    p_callers = subparsers.add_parser("callers", help="Find callers of a symbol")
    p_callers.add_argument("symbol", help="Symbol name to look up")
    p_callers.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_callers.set_defaults(func=_cmd_callers)

    # callees
    p_callees = subparsers.add_parser("callees", help="Find what a symbol calls")
    p_callees.add_argument("symbol", help="Symbol name to look up")
    p_callees.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_callees.set_defaults(func=_cmd_callees)

    # file
    p_file = subparsers.add_parser("file", help="List symbols in a file")
    p_file.add_argument("file", help="Relative file path")
    p_file.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_file.set_defaults(func=_cmd_file)

    # stats
    p_stats = subparsers.add_parser("stats", help="Show project statistics")
    p_stats.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_stats.set_defaults(func=_cmd_stats)

    # path generate
    p_path_gen = subparsers.add_parser("path", help="Generate a reading path")
    p_path_sub = p_path_gen.add_subparsers(dest="path_command", required=True)

    p_pg = p_path_sub.add_parser("generate", help="Generate a reading path")
    p_pg.add_argument("--strategy", "-s", default="complexity-ascending",
                       choices=["topological", "entry-first", "complexity-ascending"],
                       help="Path ordering strategy")
    p_pg.add_argument("--max-steps", type=int, default=200, help="Max steps (default: 200)")
    p_pg.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_pg.set_defaults(func=_cmd_path_generate)

    p_pl = p_path_sub.add_parser("list", help="List reading paths")
    p_pl.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_pl.set_defaults(func=_cmd_path_list)

    p_pw = p_path_sub.add_parser("walk", help="Walk a reading path interactively")
    p_pw.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_pw.set_defaults(func=_cmd_path_walk)

    # resume (shortcut for path walk)
    p_resume = subparsers.add_parser("resume", help="Resume the last reading session")
    p_resume.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_resume.set_defaults(func=_cmd_path_walk)

    # explain
    p_explain = subparsers.add_parser("explain", help="Get LLM explanation of a symbol")
    p_explain.add_argument("symbol", help="Symbol name to explain")
    p_explain.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_explain.add_argument("--level", "-l", default="intermediate",
                           choices=["beginner", "intermediate", "expert"])
    p_explain.add_argument("--provider", default="ollama", choices=["ollama", "gemini"])
    p_explain.add_argument("--model", "-m", help="Model name")
    p_explain.set_defaults(func=_cmd_explain)

    # serve
    p_serve = subparsers.add_parser("serve", help="Serve source files over HTTP for remote clients")
    p_serve.add_argument("path", nargs="?", default=".", help="Project root (default: .)")
    p_serve.add_argument("--port", type=int, default=11443, help="Port (default: 11443)")
    p_serve.add_argument("--host", default="0.0.0.0", help="Host (default: 0.0.0.0)")
    p_serve.set_defaults(func=_cmd_serve)

    # graph
    p_graph = subparsers.add_parser("graph", help="Symbol graph operations")
    p_graph.add_argument("--path", "-p", default=".", help="Project root (default: .)")
    p_graph.set_defaults(func=_cmd_graph_stats)

    args = parser.parse_args(argv)
    args.func(args)
