from __future__ import annotations
import os
import random
import time
from contextlib import contextmanager
from typing import Any, Callable, Optional

import sqlalchemy as sa


def is_transient_db_error(exc: Exception) -> bool:
    """Classify DB errors that are safe to retry.

    Tries to match by driver-specific exception classes if available, and
    falls back to message substring checks for portability across drivers.
    """
    try:  # psycopg2 / psycopg errors
        from psycopg2 import errors as pg_err  # type: ignore
        if isinstance(exc, (
            pg_err.DeadlockDetected,
            pg_err.SerializationFailure,
            pg_err.LockNotAvailable,
        )):
            return True
    except Exception:
        pass

    # SQLAlchemy wraps DBAPI exceptions; unwrap if possible
    orig = getattr(exc, "orig", exc)
    msg = (str(orig) or "").lower()
    return (
        "deadlock" in msg
        or "could not serialize" in msg
        or "serialization failure" in msg
        or "database is locked" in msg
        or "lock timeout" in msg
        or ("timeout" in msg and "statement" in msg)
    )


def retry_with_backoff(func: Callable[[], Any], *, attempts: int = 5, base_delay: float = 0.05) -> Any:
    """Execute callable with exponential backoff on transient DB errors.

    - Retries up to `attempts` times
    - Backoff: base_delay * 2^(n-1) + jitter (capped at 1s)
    """
    last_exc: Optional[Exception] = None
    for i in range(1, max(1, attempts) + 1):
        try:
            return func()
        except Exception as exc:  # broad by design; we classify below
            last_exc = exc
            if not is_transient_db_error(exc) or i >= attempts:
                break
            sleep_s = min(1.0, base_delay * (2 ** (i - 1)) + random.uniform(0, base_delay))
            time.sleep(sleep_s)
            continue
    if last_exc is not None:
        raise last_exc
    # Should never reach here
    return None


@contextmanager
def advisory_lock_for(conn: sa.engine.Connection, note_id: int):
    """Acquire a session-level advisory lock for a specific note_id on Postgres.

    No-op on non-Postgres dialects or when P12_ENABLE_ADVISORY_LOCKS != "1".
    The lock is released automatically on context exit.
    """
    try:
        if os.environ.get("P12_ENABLE_ADVISORY_LOCKS") != "1":
            yield
            return
        dname = getattr(conn, "engine").dialect.name
        if not str(dname).startswith("postgres"):
            yield
            return
    except Exception:
        # If we cannot determine dialect, proceed without locking
        yield
        return

    ns = 21412  # namespace constant for Paste12
    try:
        conn.execute(sa.text("SELECT pg_advisory_lock(:ns, :k)"), {"ns": ns, "k": int(note_id)})
    except Exception:
        # If lock acquisition fails for any reason, proceed without lock
        # to avoid introducing new failure modes under load.
        yield
        return
    try:
        yield
    finally:
        try:
            conn.execute(sa.text("SELECT pg_advisory_unlock(:ns, :k)"), {"ns": ns, "k": int(note_id)})
        except Exception:
            # Ignore unlock errors; connection close will release session locks
            pass
