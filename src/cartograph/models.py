"""Core data models for Cartograph."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


class SymbolKind(str, Enum):
    FUNCTION = "function"
    CLASS = "class"
    METHOD = "method"
    VARIABLE = "variable"
    MODULE = "module"
    CONSTANT = "constant"
    IMPORT = "import"


class ReferenceKind(str, Enum):
    CALLS = "calls"
    IMPORTS = "imports"
    INHERITS = "inherits"
    USES = "uses"


class Language(str, Enum):
    PYTHON = "python"
    TYPESCRIPT = "typescript"
    JAVASCRIPT = "javascript"


LANGUAGE_EXTENSIONS: dict[str, Language] = {
    ".py": Language.PYTHON,
    ".ts": Language.TYPESCRIPT,
    ".tsx": Language.TYPESCRIPT,
    ".js": Language.JAVASCRIPT,
    ".jsx": Language.JAVASCRIPT,
}


@dataclass
class Symbol:
    """A named entity extracted from source code."""

    name: str
    qualified_name: str
    kind: SymbolKind
    file_path: str  # relative to project root
    start_line: int
    end_line: int
    signature: str = ""
    docstring: str = ""
    parent_name: str = ""  # containing class/module

    @property
    def id(self) -> str:
        """Deterministic ID from file + name + line."""
        raw = f"{self.file_path}:{self.qualified_name}:{self.start_line}"
        return hashlib.sha256(raw.encode()).hexdigest()[:16]

    @property
    def line_count(self) -> int:
        return self.end_line - self.start_line + 1


@dataclass
class Reference:
    """A cross-reference between two code locations."""

    source_file: str  # file where the reference occurs
    source_name: str  # symbol making the reference
    target_name: str  # symbol being referenced
    kind: ReferenceKind
    line: int  # line of the reference


@dataclass
class SourceFile:
    """A source file in the project."""

    relative_path: str
    language: Language
    content_hash: str
    size_bytes: int

    @property
    def id(self) -> str:
        return hashlib.sha256(self.relative_path.encode()).hexdigest()[:16]


@dataclass
class ParseResult:
    """Result of parsing a single source file."""

    source_file: SourceFile
    symbols: list[Symbol] = field(default_factory=list)
    references: list[Reference] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def content_hash(path: Path) -> str:
    """SHA-256 hash of file contents."""
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()[:32]
