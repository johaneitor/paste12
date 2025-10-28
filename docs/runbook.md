# Paste12: DB contention, deadlocks, and 5xx Runbook

This runbook covers evidence collection, fast mitigation, and safe rollout/rollback for view_log deadlocks, connection exhaustion, and intermittent 5xx.

## 0. Principles
- Work in staging first. Do not touch production without an approved checkpoint and backup.
- Non-destructive changes only; avoid heavyweight DDL without a maintenance window.
- Always take a DB backup before any change that could affect the database.

## 1. Evidence collection (staging)
Artifacts path: `./p12-e2e-out/<ts>/evidence/`

Commands (read-only):
```bash
TS=$(date -u +%Y%m%d-%H%M%SZ)
mkdir -p ./p12-e2e-out/$TS/evidence
journalctl -u paste12 --since "2 hours" > ./p12-e2e-out/$TS/evidence/app.log || true
psql -c "SELECT pid, usename, state, now()-query_start AS dur, wait_event, query FROM pg_stat_activity ORDER BY query_start DESC LIMIT 100;" > ./p12-e2e-out/$TS/evidence/pg_stat_activity.txt || true
psql -c "SELECT * FROM pg_locks WHERE NOT granted;" > ./p12-e2e-out/$TS/evidence/pg_locks.txt || true
psql -c "SHOW max_connections;" > ./p12-e2e-out/$TS/evidence/pg_max_connections.txt || true
./tools/collect_prod_evidence.sh > ./p12-e2e-out/$TS/evidence/collect_prod_evidence.out 2>&1 || true
pytest -q > ./p12-e2e-out/$TS/evidence/pytest.txt 2>&1 || true
```

## 2. Fast mitigations (staging)
- Rate limit writes on view endpoints: now 60/min for `/api/notes/<id>/view` and legacy `/api/view`.
- Retry with backoff on transient DB errors (deadlocks, serialization failures).
- Optional advisory locks per note (Postgres only): enable with `P12_ENABLE_ADVISORY_LOCKS=1`.
- Pool tuning via env:
  - `P12_DB_POOL_SIZE`
  - `P12_DB_MAX_OVERFLOW`
  - `P12_DB_POOL_TIMEOUT`
- Redis-backed limiter strongly recommended in multi-instance:
  - `FLASK_LIMITER_STORAGE_URI=redis://user:pass@host:6379/0`

## 3. Backups
Create a timestamped backup directory: `./p12-e2e-out/backups/<ts>/`.

Examples (Postgres):
```bash
TS=$(date -u +%Y%m%d-%H%M%SZ)
mkdir -p ./p12-e2e-out/backups/$TS
PGDATABASE=<db> PGHOST=<host> PGUSER=<user> PGPASSWORD=*** \
  pg_dump -Fc -v -f ./p12-e2e-out/backups/$TS/paste12.dump || true
```

## 4. Terminate blocking queries safely
```sql
-- Inspect active queries
SELECT pid, usename, state, wait_event, now()-query_start AS dur, query
FROM pg_stat_activity
ORDER BY query_start ASC;

-- Terminate by pid (not cancel, if stuck)
SELECT pg_terminate_backend(<pid>);
```

## 5. Concurrency test (staging)
```bash
BASE="https://staging-your-service"  # set this
NID=$(curl -fsS -X POST -H 'Content-Type: application/json' -d '{"text":"loadtest"}' "$BASE/api/notes" | jq -r .id)
seq 200 | xargs -n1 -P32 -I{} curl -sS -o /dev/null -w "%{http_code}\n" -X POST "$BASE/api/notes/$NID/view" | sort | uniq -c > ./p12-e2e-out/$TS/view_concurrency_result.txt
```
Criteria: majority 200, <2% 5xx; views incremented ≥ 1.

## 6. Rollback procedure
- Use Git checkpoint tags: `checkpoint-<ts>`.
- To rollback code in staging:
```bash
git reset --hard checkpoint-<ts>
```
- If advisory locks caused issues: `unset P12_ENABLE_ADVISORY_LOCKS` and redeploy.

## 7. Prod rollout (manual approval)
1) Merge tested PRs to `main`.
2) Backup prod DB: `./p12-e2e-out/backups/<ts>/prod/` using `pg_dump -Fc`.
3) Set env on PROD:
```
P12_ENABLE_ADVISORY_LOCKS=1
P12_DB_POOL_SIZE=4
P12_DB_MAX_OVERFLOW=4
P12_DB_POOL_TIMEOUT=10
FLASK_LIMITER_STORAGE_URI=redis://user:pass@host:6379/0
```
4) Deploy via hook (with `--allow-deploy`).
5) Watch: `tools/deploy_watch_until_v4.sh "$BASE" 420`.
6) Monitor 60–120 min; collect evidence again.

## 8. Postmortem template
- Timeline of incidents/symptoms.
- Root cause: concurrent inserts into `view_log` using `ON CONFLICT DO NOTHING`, connection pool saturation under bursts, and per-request DDL.
- Fix summary: rate-limits, retry/backoff, optional advisory locks, pool tuning, limiter Redis storage.
- Metrics before/after: deadlock count, avg tx duration, connections used.
- Follow-ups: move DDL to migrations, batch upsert worker, pgbouncer, monitoring/alerts.
