## Paste12 Audit Report – view_log deadlocks and DB stability (2025-10-27)

### Discovery
- Intermittent 5xx, Postgres deadlocks on `view_log` inserts, connection exhaustion.
- Legacy alias `/api/view` using SQLite-only SQL in production.

### Root cause
- High concurrency `INSERT ... ON CONFLICT DO NOTHING` into `view_log` then `UPDATE notes` in same transaction → lock ordering and index page contention.
- Multiple SQLAlchemy engines in-process (fallback/compat) increasing DB connections.
- Rate-limiter using in-memory storage across replicas (ineffective under scale).

### Evidence (from repo and staging)
- `backend/modules/interactions.py` and `backend/routes.py` showed idempotent insert + counter update without backoff.
- `backend/remote_compat.py` created another engine.
- Health checks lacked DB connection metrics.

### Severity
- High. Causes availability degradation and 5xx under bursts; risk of reaching `max_connections`.

### Patch summary
- Add retry with exponential backoff and jitter for transient DB errors (deadlock/serialization/busy).
- Tighten rate limits for `/api/notes/:id/view` and legacy `/api/view`.
- Replace SQLite-only `INSERT OR IGNORE` with dialect-aware insert-ignore.
- Expose `/api/health/db` with Postgres `connections` and `max_connections`.
- Reuse primary Flask-SQLAlchemy engine in compat paths to avoid extra pools.

### Deployment plan (safe)
1. Snapshot DB backup (platform snapshot or `pg_dump` full).
2. Set `FLASK_LIMITER_STORAGE_URI=redis://...` in staging/prod.
3. Deploy to staging; run `tools/staging_load_views.sh <base> <note_id> --concurrency 50 --requests 500`.
4. Verify no deadlocks, 5xx near-zero, health shows connections < 80% of `max_connections`.
5. Schedule prod deploy; monitor 60–120 minutes; rollback if error rates increase.

### Rollback
- Revert branch and redeploy. No schema changes.
