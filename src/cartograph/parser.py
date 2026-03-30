"""Tree-sitter based source code parser for symbol and reference extraction."""

from __future__ import annotations

import logging
from pathlib import Path

import tree_sitter
import tree_sitter_javascript as tsjs
import tree_sitter_python as tspy
import tree_sitter_typescript as tsts

from .models import (
    Language,
    ParseResult,
    Reference,
    ReferenceKind,
    SourceFile,
    Symbol,
    SymbolKind,
    content_hash,
)

log = logging.getLogger(__name__)

# Initialize languages and parsers
_LANGUAGES: dict[Language, tree_sitter.Language] = {
    Language.PYTHON: tree_sitter.Language(tspy.language()),
    Language.TYPESCRIPT: tree_sitter.Language(tsts.language_typescript()),
    Language.JAVASCRIPT: tree_sitter.Language(tsjs.language()),
}


def _get_parser(lang: Language) -> tree_sitter.Parser:
    """Create a parser for the given language."""
    return tree_sitter.Parser(_LANGUAGES[lang])


def _node_text(node: tree_sitter.Node) -> str:
    """Extract text content from a tree-sitter node."""
    return node.text.decode("utf8") if node.text else ""


def _get_docstring(node: tree_sitter.Node) -> str:
    """Extract docstring from a function/class body (Python)."""
    body = node.child_by_field_name("body")
    if body and body.child_count > 0:
        first = body.children[0]
        if first.type == "expression_statement" and first.child_count > 0:
            expr = first.children[0]
            if expr.type == "string":
                text = _node_text(expr)
                # Strip triple quotes
                for q in ('"""', "'''"):
                    if text.startswith(q) and text.endswith(q):
                        return text[3:-3].strip()
                return text.strip("\"'").strip()
    return ""


def _build_signature(node: tree_sitter.Node) -> str:
    """Build a function signature string from parameters node."""
    name_node = node.child_by_field_name("name")
    params_node = node.child_by_field_name("parameters")
    name = _node_text(name_node) if name_node else "?"
    params = _node_text(params_node) if params_node else "()"
    ret = node.child_by_field_name("return_type")
    ret_str = f" -> {_node_text(ret)}" if ret else ""
    return f"{name}{params}{ret_str}"


# ---------------------------------------------------------------------------
# Python extractor
# ---------------------------------------------------------------------------


def _extract_python_symbols(
    tree: tree_sitter.Tree,
    file_path: str,
) -> tuple[list[Symbol], list[Reference]]:
    """Extract symbols and references from a Python AST."""
    symbols: list[Symbol] = []
    references: list[Reference] = []

    def _walk(node: tree_sitter.Node, parent_qname: str = "") -> None:
        if node.type == "function_definition":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = _node_text(name_node)
                qname = f"{parent_qname}.{name}" if parent_qname else name
                kind = SymbolKind.METHOD if parent_qname else SymbolKind.FUNCTION
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=qname,
                        kind=kind,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                        signature=_build_signature(node),
                        docstring=_get_docstring(node),
                        parent_name=parent_qname,
                    )
                )
                # Extract call references from function body
                _extract_python_calls(node, file_path, qname, references)
                # Recurse into nested definitions
                body = node.child_by_field_name("body")
                if body:
                    for child in body.children:
                        _walk(child, qname)
                return  # Don't recurse into children again

        elif node.type == "class_definition":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = _node_text(name_node)
                qname = f"{parent_qname}.{name}" if parent_qname else name
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=qname,
                        kind=SymbolKind.CLASS,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                        docstring=_get_docstring(node),
                        parent_name=parent_qname,
                    )
                )
                # Extract base classes as inheritance references
                bases = node.child_by_field_name("superclasses")
                if bases:
                    for child in bases.children:
                        if child.type in ("identifier", "attribute"):
                            references.append(
                                Reference(
                                    source_file=file_path,
                                    source_name=qname,
                                    target_name=_node_text(child),
                                    kind=ReferenceKind.INHERITS,
                                    line=child.start_point.row + 1,
                                )
                            )
                # Recurse into class body
                body = node.child_by_field_name("body")
                if body:
                    for child in body.children:
                        _walk(child, qname)
                return

        elif node.type in ("import_statement", "import_from_statement"):
            _extract_python_import(node, file_path, references)

        elif node.type == "assignment" and not parent_qname:
            # Top-level assignments as constants/variables
            left = node.child_by_field_name("left")
            if left and left.type == "identifier":
                name = _node_text(left)
                # Heuristic: UPPER_CASE = constant
                kind = SymbolKind.CONSTANT if name.isupper() else SymbolKind.VARIABLE
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=name,
                        kind=kind,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                    )
                )

        # Default: recurse into children
        for child in node.children:
            _walk(child, parent_qname)

    _walk(tree.root_node)
    return symbols, references


def _extract_python_calls(
    func_node: tree_sitter.Node,
    file_path: str,
    caller_name: str,
    references: list[Reference],
) -> None:
    """Walk a function body and extract call expressions."""

    def _find_calls(node: tree_sitter.Node) -> None:
        if node.type == "call":
            fn = node.child_by_field_name("function")
            if fn:
                target = _node_text(fn)
                references.append(
                    Reference(
                        source_file=file_path,
                        source_name=caller_name,
                        target_name=target,
                        kind=ReferenceKind.CALLS,
                        line=node.start_point.row + 1,
                    )
                )
        # Don't recurse into nested function/class definitions
        if node.type in ("function_definition", "class_definition"):
            return
        for child in node.children:
            _find_calls(child)

    body = func_node.child_by_field_name("body")
    if body:
        _find_calls(body)


def _extract_python_import(
    node: tree_sitter.Node,
    file_path: str,
    references: list[Reference],
) -> None:
    """Extract import references from import statements."""
    if node.type == "import_statement":
        for child in node.children:
            if child.type == "dotted_name":
                references.append(
                    Reference(
                        source_file=file_path,
                        source_name="<module>",
                        target_name=_node_text(child),
                        kind=ReferenceKind.IMPORTS,
                        line=node.start_point.row + 1,
                    )
                )
    elif node.type == "import_from_statement":
        module_node = node.child_by_field_name("module_name")
        module_name = _node_text(module_node) if module_node else ""
        for child in node.children:
            if child.type == "import_from_names" or child.type == "aliased_import":
                for name_child in child.children if child.type == "import_from_names" else [child]:
                    if name_child.type in ("dotted_name", "identifier"):
                        imported = _node_text(name_child)
                        target = f"{module_name}.{imported}" if module_name else imported
                        references.append(
                            Reference(
                                source_file=file_path,
                                source_name="<module>",
                                target_name=target,
                                kind=ReferenceKind.IMPORTS,
                                line=node.start_point.row + 1,
                            )
                        )
            elif child.type in ("dotted_name", "identifier") and child != module_node:
                imported = _node_text(child)
                if imported not in ("import", "from", ",", "."):
                    target = f"{module_name}.{imported}" if module_name else imported
                    references.append(
                        Reference(
                            source_file=file_path,
                            source_name="<module>",
                            target_name=target,
                            kind=ReferenceKind.IMPORTS,
                            line=node.start_point.row + 1,
                        )
                    )


# ---------------------------------------------------------------------------
# TypeScript/JavaScript extractor
# ---------------------------------------------------------------------------


def _extract_ts_symbols(
    tree: tree_sitter.Tree,
    file_path: str,
    lang: Language,
) -> tuple[list[Symbol], list[Reference]]:
    """Extract symbols and references from a TypeScript/JavaScript AST."""
    symbols: list[Symbol] = []
    references: list[Reference] = []

    def _walk(node: tree_sitter.Node, parent_qname: str = "") -> None:
        if node.type == "function_declaration":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = _node_text(name_node)
                qname = f"{parent_qname}.{name}" if parent_qname else name
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=qname,
                        kind=SymbolKind.FUNCTION,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                        signature=_build_ts_signature(node),
                        parent_name=parent_qname,
                    )
                )
                _extract_ts_calls(node, file_path, qname, references)

        elif node.type == "class_declaration":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = _node_text(name_node)
                qname = f"{parent_qname}.{name}" if parent_qname else name
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=qname,
                        kind=SymbolKind.CLASS,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                        parent_name=parent_qname,
                    )
                )
                body = node.child_by_field_name("body")
                if body:
                    for child in body.children:
                        _walk(child, qname)
                return

        elif node.type == "method_definition":
            name_node = node.child_by_field_name("name")
            if name_node:
                name = _node_text(name_node)
                qname = f"{parent_qname}.{name}" if parent_qname else name
                symbols.append(
                    Symbol(
                        name=name,
                        qualified_name=qname,
                        kind=SymbolKind.METHOD,
                        file_path=file_path,
                        start_line=node.start_point.row + 1,
                        end_line=node.end_point.row + 1,
                        parent_name=parent_qname,
                    )
                )
                _extract_ts_calls(node, file_path, qname, references)

        elif node.type in ("lexical_declaration", "variable_declaration"):
            for decl in node.children:
                if decl.type == "variable_declarator":
                    name_node = decl.child_by_field_name("name")
                    value_node = decl.child_by_field_name("value")
                    if name_node:
                        name = _node_text(name_node)
                        # Arrow functions / function expressions as named symbols
                        if value_node and value_node.type in (
                            "arrow_function",
                            "function_expression",
                        ):
                            qname = f"{parent_qname}.{name}" if parent_qname else name
                            symbols.append(
                                Symbol(
                                    name=name,
                                    qualified_name=qname,
                                    kind=SymbolKind.FUNCTION,
                                    file_path=file_path,
                                    start_line=node.start_point.row + 1,
                                    end_line=node.end_point.row + 1,
                                    parent_name=parent_qname,
                                )
                            )
                            _extract_ts_calls(value_node, file_path, qname, references)
                        elif not parent_qname:
                            symbols.append(
                                Symbol(
                                    name=name,
                                    qualified_name=name,
                                    kind=SymbolKind.VARIABLE,
                                    file_path=file_path,
                                    start_line=node.start_point.row + 1,
                                    end_line=node.end_point.row + 1,
                                )
                            )

        elif node.type == "import_statement":
            _extract_ts_import(node, file_path, references)

        for child in node.children:
            _walk(child, parent_qname)

    _walk(tree.root_node)
    return symbols, references


def _build_ts_signature(node: tree_sitter.Node) -> str:
    """Build function signature for TS/JS."""
    name_node = node.child_by_field_name("name")
    params_node = node.child_by_field_name("parameters")
    name = _node_text(name_node) if name_node else "?"
    params = _node_text(params_node) if params_node else "()"
    return f"{name}{params}"


def _extract_ts_calls(
    node: tree_sitter.Node,
    file_path: str,
    caller_name: str,
    references: list[Reference],
) -> None:
    """Extract call expressions from TS/JS."""

    def _find_calls(n: tree_sitter.Node) -> None:
        if n.type == "call_expression":
            fn = n.child_by_field_name("function")
            if fn:
                references.append(
                    Reference(
                        source_file=file_path,
                        source_name=caller_name,
                        target_name=_node_text(fn),
                        kind=ReferenceKind.CALLS,
                        line=n.start_point.row + 1,
                    )
                )
        if n.type in ("function_declaration", "class_declaration", "arrow_function"):
            return
        for child in n.children:
            _find_calls(child)

    body = node.child_by_field_name("body")
    if body:
        _find_calls(body)


def _extract_ts_import(
    node: tree_sitter.Node,
    file_path: str,
    references: list[Reference],
) -> None:
    """Extract import references from TS/JS import statements."""
    source = node.child_by_field_name("source")
    if source:
        module = _node_text(source).strip("\"'")
        references.append(
            Reference(
                source_file=file_path,
                source_name="<module>",
                target_name=module,
                kind=ReferenceKind.IMPORTS,
                line=node.start_point.row + 1,
            )
        )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_file(path: Path, project_root: Path) -> ParseResult:
    """Parse a single source file and extract symbols + references.

    Args:
        path: Absolute path to the source file.
        project_root: Absolute path to the project root (for relative paths).

    Returns:
        ParseResult with symbols, references, and any errors.
    """
    relative = str(path.relative_to(project_root))
    suffix = path.suffix.lower()

    from .models import LANGUAGE_EXTENSIONS

    lang = LANGUAGE_EXTENSIONS.get(suffix)
    if lang is None:
        return ParseResult(
            source_file=SourceFile(
                relative_path=relative,
                language=Language.PYTHON,  # placeholder
                content_hash="",
                size_bytes=0,
            ),
            errors=[f"Unsupported file extension: {suffix}"],
        )

    try:
        source_bytes = path.read_bytes()
    except OSError as e:
        return ParseResult(
            source_file=SourceFile(
                relative_path=relative,
                language=lang,
                content_hash="",
                size_bytes=0,
            ),
            errors=[f"Could not read file: {e}"],
        )

    src_file = SourceFile(
        relative_path=relative,
        language=lang,
        content_hash=content_hash(path),
        size_bytes=len(source_bytes),
    )

    try:
        parser = _get_parser(lang)
        tree = parser.parse(source_bytes)
    except Exception as e:
        return ParseResult(source_file=src_file, errors=[f"Parse error: {e}"])

    if lang == Language.PYTHON:
        symbols, refs = _extract_python_symbols(tree, relative)
    elif lang in (Language.TYPESCRIPT, Language.JAVASCRIPT):
        symbols, refs = _extract_ts_symbols(tree, relative, lang)
    else:
        symbols, refs = [], []

    return ParseResult(source_file=src_file, symbols=symbols, references=refs)
