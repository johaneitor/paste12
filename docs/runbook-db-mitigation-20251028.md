## Runbook – Mitigación de deadlocks y agotamiento de conexiones (2025-10-28)

### Objetivo
Operar y estabilizar el entorno ante picos de tráfico que afecten `view_log` y el pool de conexiones.

### Toggles / Env
- `P12_ENABLE_ADVISORY_LOCKS=1` (serializa por nota en Postgres, lock transaccional corto)
- `P12_DB_POOL_SIZE` (p.ej. 8–10), `P12_DB_MAX_OVERFLOW` (5–10), `P12_DB_POOL_TIMEOUT` (10–20)
- `FLASK_LIMITER_STORAGE_URI=redis://user:pass@host:6379/0`

### Procedimientos
- Modo read-only (temporal): incrementar límites de rate limit para write endpoints a valores muy bajos o activar maintenance mode a nivel proxy si aplica.
- Reinicio controlado de workers si hay fugas de conexiones (graceful stop, sin cortar tráfico activo).
- Diagnóstico rápido (no destructivo):
  - `tools/collect_prod_evidence.sh` (requiere `psql` si se desea `pg_*`).
  - Manual:
    - `SELECT pid, state, now()-query_start AS age, wait_event, left(query,160) FROM pg_stat_activity ORDER BY query_start DESC LIMIT 50;`
    - `SELECT * FROM pg_locks WHERE NOT granted;`
    - `SELECT count(*) FROM pg_stat_activity;` y `SHOW max_connections;`
- Identificar y terminar transacciones bloqueantes (con autorización):
  - `SELECT pid, now()-query_start AS age, query FROM pg_stat_activity WHERE state='active' ORDER BY age DESC LIMIT 20;`
  - `SELECT pg_terminate_backend(<pid>);` (último recurso)

### Límites y protección
- Alias legado `/api/view`: `5/min` por IP. Endpoints canónicos ya poseen límites.
- Preferir Redis como storage del rate-limiter en producción.

### Recomendaciones de capacidad
- Usar pgbouncer (transaction pooling). Apuntar la app a pgbouncer y fijar `pool_size` bajo.
- Alertar cuando conexiones activas > 80% de `max_connections`.

### Rollback
- Deshabilitar `P12_ENABLE_ADVISORY_LOCKS` y retornar límites a valores previos.
- Reversa a imagen/commit anterior si el problema persiste.
