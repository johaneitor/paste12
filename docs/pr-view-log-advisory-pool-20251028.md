# PR: Mitigación de deadlocks en view_log, advisory locks opcional y pool parametrizable

## Summary
- Reduce 5xx por contención en `view_log` añadiendo retry/backoff alrededor del bloque transaccional y un flag opcional de advisory lock por nota.
- Endurece rate limit en alias legado `/api/view` a `5/min`.
- Parametriza el pool de SQLAlchemy por entorno (`P12_DB_POOL_*`).
- Añade script `tools/collect_prod_evidence.sh` para evidencia y diagnósticos.

## Details
- `backend/modules/interactions.py`: advisory lock transaccional (flag `P12_ENABLE_ADVISORY_LOCKS`), mantiene DDL idempotente y retry.
- `backend/routes.py`: alias `/api/view` con límite `5/min` y advisory lock opcional.
- `backend/__init__.py`: lee `P12_DB_POOL_SIZE`, `P12_DB_MAX_OVERFLOW`, `P12_DB_POOL_TIMEOUT` y mantiene `pool_pre_ping`/`pool_recycle`.
- `tools/collect_prod_evidence.sh`: recolecta `pg_stat_activity`, `pg_locks`, `pg_stat_database`, health endpoints y env (enmascarado).

## Test plan
- Unit: `tests/test_views_concurrency.py` (idempotencia y concurrencia básica en SQLite) sigue pasando.
- Staging: 100–300 requests concurrentes a `/api/notes/{id}/view`; verificar ausencia de deadlocks y tasa de 503 baja (<2%).
- Health: `/api/health/db` muestra uso de conexiones y `max_connections`.

## Rollback
- Revertir el deploy; no hay migraciones destructivas. Desactivar `P12_ENABLE_ADVISORY_LOCKS` para volver a la ruta previa.

## Ops notes
- Configurar `FLASK_LIMITER_STORAGE_URI=redis://...` en prod.
- Recomendado pgbouncer (transaction pooling).
