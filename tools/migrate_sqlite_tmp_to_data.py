#!/usr/bin/env python3
"""
Utility to migrate the legacy /tmp/paste12.db file into the new persistent location.

Usage:
    python tools/migrate_sqlite_tmp_to_data.py

Optional env vars:
    P12_SQLITE_SRC    → override the source file (defaults to /tmp/paste12.db)
    P12_SQLITE_PATH   → override the destination (same env used by the app)
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from backend.db_config import resolve_sqlite_target  # noqa: E402


def main() -> int:
    src = Path(os.environ.get("P12_SQLITE_SRC", "/tmp/paste12.db"))
    uri, dest_path = resolve_sqlite_target()

    if dest_path is None:
        print(f"[p12:migrate] Destination is configured as URI ({uri}); nothing to copy.", file=sys.stderr)
        return 0

    if not src.exists():
        print(f"[p12:migrate] Source {src} does not exist; nothing to do.", file=sys.stderr)
        return 0

    try:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass

    shutil.copy2(src, dest_path)
    print(f"[p12:migrate] Copied {src} -> {dest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
