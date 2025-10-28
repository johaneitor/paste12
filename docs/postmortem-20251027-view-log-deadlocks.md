## Postmortem – view_log deadlocks and connection exhaustion (2025-10-27)

### Timeline
- T-? days: Intermittent 5xx observed during traffic bursts.
- T-1: Reports of Postgres deadlocks and max connections exhaustion.
- T0: Rollout of retries/backoff, rate limits, alias fix, and health metrics.

### Impact
- Elevated 5xx and latency; periodic denial of service for view increments.

### Root causes
- Concurrency on `view_log` unique index and subsequent `UPDATE notes` in same transaction.
- Multiple engines increasing connections; ineffective rate-limiting storage across replicas.

### Mitigations implemented
- Retries with backoff for transient DB errors; per-endpoint rate limiting.
- Alias fixed to use dialect-aware SQL; health endpoint exposes connection metrics.
- Engine reuse to consolidate pools.

### Preventive actions
- Adopt pgbouncer in transaction pooling mode.
- Monitor `pg_stat_activity` > 80% of `max_connections` with alerts.
- Add load tests in CI staging for write endpoints.
