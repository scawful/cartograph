"""Utility functions for testing cross-references."""

from .main import FileProcessor, validate


def batch_validate(paths: list) -> list:
    """Validate multiple paths."""
    return [p for p in paths if validate(p)]


def create_processor(root) -> FileProcessor:
    """Factory for FileProcessor."""
    return FileProcessor(root)
