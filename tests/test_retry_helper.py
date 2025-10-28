import time
import types
from backend.utils.db import retry_with_backoff, is_transient_db_error


def test_retry_with_backoff_eventual_success():
    attempts = {"n": 0}

    class Deadlock(Exception):
        pass

    def fn():
        attempts["n"] += 1
        if attempts["n"] < 3:
            # Simulate a DBAPI-wrapped exception with "orig" carrying message
            exc = Deadlock("deadlock detected")
            exc.orig = exc  # mimic SQLAlchemy-wrapped exception
            raise exc
        return "ok"

    t0 = time.time()
    out = retry_with_backoff(fn, attempts=5, base_delay=0.001)
    dt = time.time() - t0
    assert out == "ok"
    assert attempts["n"] == 3
    assert dt < 0.2  # backoff kept small


def test_retry_with_backoff_non_transient_raises():
    def fn():
        raise RuntimeError("permanent failure")

    try:
        retry_with_backoff(fn, attempts=5, base_delay=0.001)
    except Exception as e:
        assert isinstance(e, RuntimeError)
    else:
        raise AssertionError("expected exception to propagate")
