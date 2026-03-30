"""LLM-powered code explanation service with content-hash caching.

Explanations are cached per (symbol_id, content_hash, level) so they
auto-invalidate when code changes. Supports Ollama (local/free) and
Gemini (higher quality) backends.
"""

from __future__ import annotations

import hashlib
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .storage import CartographDB

log = logging.getLogger(__name__)

# Default explanation prompt template
_EXPLAIN_PROMPT = """Explain the following {kind} from a codebase. Be concise (2-4 paragraphs).

Level: {level}
- beginner: Explain what this does in plain language, no jargon.
- intermediate: Explain purpose, design decisions, and how it fits the system.
- expert: Focus on edge cases, performance, tradeoffs, and alternatives.

Symbol: {qualified_name}
File: {file_path}:{start_line}-{end_line}
{signature_line}
{docstring_line}

Source code:
```{language}
{source_code}
```

{context}

Explain this {kind}:"""


def _build_prompt(
    symbol_info: dict,
    source_code: str,
    context: str,
    level: str,
) -> str:
    """Build an explanation prompt from symbol info and source."""
    sig = symbol_info.get("signature", "")
    doc = symbol_info.get("docstring", "")

    return _EXPLAIN_PROMPT.format(
        kind=symbol_info.get("kind", "symbol"),
        level=level,
        qualified_name=symbol_info.get("qualified_name", symbol_info.get("name", "?")),
        file_path=symbol_info.get("file_path", "?"),
        start_line=symbol_info.get("start_line", "?"),
        end_line=symbol_info.get("end_line", "?"),
        signature_line=f"Signature: {sig}" if sig else "",
        docstring_line=f"Docstring: {doc}" if doc else "",
        source_code=source_code,
        language=symbol_info.get("language", "python"),
        context=f"Context:\n{context}" if context else "",
    )


class ExplainService:
    """Generates and caches LLM explanations for code symbols."""

    def __init__(
        self,
        db: CartographDB,
        project_root: Path,
        provider: str = "ollama",
        model: str | None = None,
        base_url: str | None = None,
    ):
        self.db = db
        self.project_root = project_root
        self.provider = provider
        self.model = model or self._default_model()
        self.base_url = base_url or self._default_url()

    def _default_model(self) -> str:
        if self.provider == "ollama":
            return "llama3.2"
        elif self.provider == "gemini":
            return "gemini-2.0-flash"
        return "llama3.2"

    def _default_url(self) -> str:
        if self.provider == "ollama":
            return "http://localhost:11434"
        elif self.provider == "gemini":
            return "https://generativelanguage.googleapis.com"
        return "http://localhost:11434"

    def explain_symbol(
        self,
        symbol_id: str,
        level: str = "intermediate",
        context: str = "",
    ) -> dict[str, Any]:
        """Explain a symbol. Returns cached result if available and still valid.

        Returns:
            {"explanation": str, "cached": bool, "model": str}
        """
        # Look up symbol info
        row = self.db.conn.execute(
            """
            SELECT s.name, s.qualified_name, s.kind, s.start_line, s.end_line,
                   s.signature, s.docstring,
                   sf.relative_path, sf.content_hash, sf.language, sf.id
            FROM symbols s
            JOIN source_files sf ON s.file_id = sf.id
            WHERE s.id = ?
            """,
            (symbol_id,),
        ).fetchone()

        if not row:
            return {"explanation": f"Symbol {symbol_id} not found.", "cached": False, "model": ""}

        symbol_info = {
            "name": row[0],
            "qualified_name": row[1],
            "kind": row[2],
            "start_line": row[3],
            "end_line": row[4],
            "signature": row[5] or "",
            "docstring": row[6] or "",
            "file_path": row[7],
            "language": row[9] or "python",
        }
        content_hash = row[8]
        file_id = row[10]

        # Check cache
        cache_id = hashlib.sha256(
            f"{symbol_id}:{content_hash}:{level}".encode()
        ).hexdigest()[:16]

        cached = self.db.conn.execute(
            "SELECT explanation, model_used FROM explanations WHERE id = ? AND content_hash = ?",
            (cache_id, content_hash),
        ).fetchone()

        if cached:
            return {"explanation": cached[0], "cached": True, "model": cached[1] or ""}

        # Read source code
        source_path = self.project_root / symbol_info["file_path"]
        source_code = self._read_symbol_source(
            source_path, symbol_info["start_line"], symbol_info["end_line"]
        )

        # Build prompt and call LLM
        prompt = _build_prompt(symbol_info, source_code, context, level)

        try:
            explanation = self._call_llm(prompt)
        except Exception as e:
            log.error("LLM call failed: %s", e)
            return {
                "explanation": f"Could not generate explanation: {e}",
                "cached": False,
                "model": self.model,
            }

        # Cache the result
        now = datetime.now(timezone.utc).isoformat()
        self.db.conn.execute(
            """
            INSERT OR REPLACE INTO explanations
            (id, symbol_id, file_id, content_hash, level, explanation, model_used, generated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (cache_id, symbol_id, file_id, content_hash, level, explanation, self.model, now),
        )
        self.db.conn.commit()

        return {"explanation": explanation, "cached": False, "model": self.model}

    def _read_symbol_source(self, path: Path, start_line: int, end_line: int) -> str:
        """Read the source code for a symbol."""
        try:
            lines = path.read_text().splitlines()
            # Include a few lines of context before and after
            start = max(0, start_line - 2)
            end = min(len(lines), end_line + 1)
            return "\n".join(lines[start:end])
        except OSError:
            return "(source code unavailable)"

    def _call_llm(self, prompt: str) -> str:
        """Call the LLM provider. Lazy-imports httpx to avoid import-time cost."""
        import httpx

        if self.provider == "ollama":
            return self._call_ollama(httpx, prompt)
        elif self.provider == "gemini":
            return self._call_gemini(httpx, prompt)
        else:
            raise ValueError(f"Unknown provider: {self.provider}")

    def _call_ollama(self, httpx_mod: Any, prompt: str) -> str:
        """Call Ollama API."""
        resp = httpx_mod.post(
            f"{self.base_url}/api/generate",
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.3, "num_predict": 1024},
            },
            timeout=60.0,
        )
        resp.raise_for_status()
        return resp.json()["response"]

    def _call_gemini(self, httpx_mod: Any, prompt: str) -> str:
        """Call Gemini API."""
        import os

        api_key = os.environ.get("GEMINI_API_KEY", "")
        if not api_key:
            raise ValueError("GEMINI_API_KEY not set")

        resp = httpx_mod.post(
            f"{self.base_url}/v1beta/models/{self.model}:generateContent",
            params={"key": api_key},
            json={
                "contents": [{"parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.3, "maxOutputTokens": 1024},
            },
            timeout=60.0,
        )
        resp.raise_for_status()
        data = resp.json()
        return data["candidates"][0]["content"]["parts"][0]["text"]
