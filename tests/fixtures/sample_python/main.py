"""Sample Python module for testing Cartograph parsing."""

import os
from pathlib import Path

MAX_SIZE = 1024


class FileProcessor:
    """Processes files in a directory."""

    def __init__(self, root: Path):
        self.root = root

    def process(self, path: Path) -> str:
        """Process a single file."""
        content = self._read(path)
        return self._transform(content)

    def _read(self, path: Path) -> str:
        return path.read_text()

    def _transform(self, content: str) -> str:
        return content.strip()


def validate(path: Path) -> bool:
    """Validate a file exists and is not too large."""
    if not path.exists():
        return False
    return path.stat().st_size <= MAX_SIZE


def run(root: Path) -> None:
    """Entry point: process all files in root."""
    processor = FileProcessor(root)
    for child in root.iterdir():
        if child.is_file() and validate(child):
            result = processor.process(child)
            print(result)
