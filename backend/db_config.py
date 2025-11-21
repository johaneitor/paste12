from __future__ import annotations

import os
from pathlib import Path
from typing import Tuple, Optional

_FALLBACK_SQLITE = "/data/paste12.db"


def _normalize_path(raw: str) -> Path:
    """
    Expand ~ and relative paths for SQLite files to an absolute Path.
    """
    path = Path(raw).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return path


def resolve_sqlite_target() -> Tuple[str, Optional[Path]]:
    """
    Return a tuple (uri, path) based on P12_SQLITE_PATH.
    - If P12_SQLITE_PATH already looks like a sqlite:// URI, it is returned as-is and
      the path component is None (because parsing may be ambiguous).
    - Otherwise, ensure the parent directory exists and return the absolute path.
    """
    raw = (os.environ.get("P12_SQLITE_PATH") or _FALLBACK_SQLITE).strip()
    if raw.startswith("sqlite:"):
        return raw, None
    path = _normalize_path(raw)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        # Fallback to ./data if /data is not writable (e.g., local dev without sudo)
        fallback = _normalize_path(f"./data/{path.name}")
        try:
            fallback.parent.mkdir(parents=True, exist_ok=True)
            path = fallback
        except Exception:
            pass
    return f"sqlite:///{path.as_posix()}", path


def resolve_sqlite_uri() -> str:
    """
    Convenience helper to fetch only the URI.
    """
    uri, _ = resolve_sqlite_target()
    return uri
