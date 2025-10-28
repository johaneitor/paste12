## Runbook – Deadlocks and DB exhaustion mitigation

### Immediate actions (prod)
- Increase write rate-limits on `/api/notes/:id/view` and `/api/view` via env or WAF.
- If deadlocks spike: gracefully shed write load (maintenance mode for writes) temporarily.
- Identify blocking sessions and consider termination with authorization:
  - `SELECT pid, state, wait_event, query_start, query FROM pg_stat_activity ORDER BY query_start DESC LIMIT 50;`
  - `SELECT * FROM pg_locks WHERE NOT granted;`
  - `SELECT pg_terminate_backend(<pid>);` (last resort)
- If nearing `max_connections`: recycle app workers, restart pgbouncer, or temporarily increase `max_connections` carefully.

### Diagnostics commands
- Connections: `SELECT count(*) FROM pg_stat_activity;` and `SHOW max_connections;`
- DB stats: `SELECT * FROM pg_stat_database;`
- Long running: query `pg_stat_activity` by duration.

### Configuration recommendations
- Use pgbouncer (transaction pooling) in front of Postgres.
- Set `RATELIMIT_STORAGE_URI=redis://...` for Flask-Limiter.
- SQLAlchemy pool: `pool_size=5..10`, `max_overflow=5..10`, `pool_pre_ping=true`, `pool_recycle=280`.

### Post-deploy validation
- `/api/health/db` shows `connections < 0.8 * max_connections`.
- Smoke test `/api/notes/:id/view` -> 200 and monotonic `views`.
