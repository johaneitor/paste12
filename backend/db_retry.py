"""
Safe helper for inserting into view_log with retry/backoff to mitigate deadlocks.
Uses DATABASE_URL env var. Works with psycopg2 or SQLAlchemy raw connection.
"""
import os
import time
import random
from contextlib import contextmanager

DATABASE_URL = os.environ.get("DATABASE_URL")

# Optional import detection
try:
    import psycopg2
    import psycopg2.extras
    import psycopg2.errors as pg_errors
    HAS_PSYCOPG2 = True
except Exception:
    HAS_PSYCOPG2 = False

# Retry params from env with defaults
MAX_RETRIES = int(os.environ.get("P12_DB_INSERT_MAX_RETRIES", "5"))
BASE_SLEEP = float(os.environ.get("P12_DB_INSERT_BASE_SLEEP", "0.02"))
MAX_SLEEP = float(os.environ.get("P12_DB_INSERT_MAX_SLEEP", "0.5"))

def _sleep_with_backoff(attempt):
    sleep = min(MAX_SLEEP, BASE_SLEEP * (2 ** attempt)) 
    sleep = sleep * (0.5 + random.random() * 0.5)  # jitter
    time.sleep(sleep)

def insert_view_log_with_retry(note_id, fingerprint, day, created_at):
    """
    Attempts to INSERT ... ON CONFLICT DO NOTHING with retries on deadlock/serialization failures.
    Returns True if insert attempted (or conflict) ; raises exception if unrecoverable.
    """
    if not HAS_PSYCOPG2:
        raise RuntimeError("psycopg2 not installed in runtime; install it to use db_retry helper")

    # Build SQL (parameterized)
    sql = """
    INSERT INTO view_log(note_id, fingerprint, day, created_at)
    VALUES (%s, %s, %s, %s)
    ON CONFLICT(note_id, fingerprint, day) DO NOTHING
    """
    params = (note_id, fingerprint, day, created_at)

    attempt = 0
    while True:
        attempt += 1
        try:
            # connect, execute, commit
            conn = psycopg2.connect(os.environ["DATABASE_URL"], connect_timeout=5)
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(sql, params)
            conn.close()
            return True
        except Exception as e:
            # detect deadlock or serialization errors
            name = e.__class__.__name__
            msg = str(e).lower()
            is_deadlock = False
            if HAS_PSYCOPG2:
                # psycopg2 raises specific exceptions in pg_errors:
                try:
                    if isinstance(e, pg_errors.DeadlockDetected) or 'deadlock' in msg:
                        is_deadlock = True
                except Exception:
                    is_deadlock = ('deadlock' in msg)
            else:
                is_deadlock = ('deadlock' in msg or 'could not serialize' in msg)

            if is_deadlock and attempt <= MAX_RETRIES:
                _sleep_with_backoff(attempt)
                continue
            # otherwise re-raise after closing conn
            try:
                conn.close()
            except Exception:
                pass
            raise

