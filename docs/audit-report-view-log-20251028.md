## Paste12 Audit Report – view_log deadlocks and DB stability (2025-10-28)

### Discovery
- Errores 5xx intermitentes, deadlocks en inserciones a `view_log`, agotamiento de conexiones (Postgres: remaining connection slots are reserved...).
- Alias legado `/api/view` activo y con límites suaves; alta concurrencia sobre el mismo índice único.
- Varios paths podían crear Engines adicionales (shims/compat), elevando el número de conexiones.

### Evidence (cómo recolectar y dónde queda)
- Ejecutar `tools/collect_prod_evidence.sh` con `REMOTE_BASE_URL` y `DATABASE_URL` en el entorno.
- Exporta a `./p12-e2e-out/logs/<timestamp>/`: `app_env.txt`, `http_health.txt`, `pg_diag.txt`, `app_last_24h.log`, `pg_last_24h.log` (si journalctl disponible).
- Consultas incluidas: `pg_stat_activity`, `pg_locks` (NOT granted), `pg_stat_database`, conteo de conexiones y `max_connections`.

### Root cause
- Alta concurrencia de `INSERT ... ON CONFLICT DO NOTHING` en `view_log` seguida de `UPDATE notes` en la misma transacción → contención en páginas de índice + orden de locks.
- Pool de conexiones no parametrizado por entorno y posibilidad de múltiples Engines → picos que saturan `max_connections`.
- Rate limiting con storage en memoria (por defecto) no efectivo en despliegues multi-réplica.

### Severity
- Alta: afecta disponibilidad (5xx, 503 por lock) y puede degradar la experiencia bajo carga. Riesgo de cascada al agotar conexiones.

### Changes implemented (safe, minimal)
- Retries con backoff exponencial y jitter alrededor del bloque transaccional de view insert + counter update (ya presentes; reafirmados).
- Opción de advisory lock por nota (feature flag `P12_ENABLE_ADVISORY_LOCKS=1`) con `lock_timeout` bajo para forzar retry en contención.
- Límite más estricto en alias legado `/api/view` (`5/min`) para reducir presión en producción.
- Pool SQLAlchemy parametrizable por entorno: `P12_DB_POOL_SIZE`, `P12_DB_MAX_OVERFLOW`, `P12_DB_POOL_TIMEOUT` (por defecto conservadores: 8/8/10s).
- Health DB ampliado: reporta conexiones usadas y `max_connections` si el dialecto es Postgres.
- Script de evidencia: `tools/collect_prod_evidence.sh`.

### Proposed mitigations (operativas)
- Configurar `FLASK_LIMITER_STORAGE_URI=redis://...` en producción.
- Colocar pgbouncer en modo transaction pooling delante de Postgres, objetivo: 20–50 conexiones desde app.
- Ajustar `pool_size` <= 10 por instancia y mantener `pool_pre_ping` y `pool_recycle` activos.

### Deployment plan (staging-first)
1) Crear branch `audit-fix/view-log-advisory-pool-20251028` y abrir PR.
2) Desplegar a staging con `P12_ENABLE_ADVISORY_LOCKS=1` inicialmente, límites por alias activos.
3) Ejecutar ráfagas concurrentes a `/api/notes/{id}/view` en staging (100–300 reqs) y verificar: sin deadlocks, 200/503 bajos, contadores consistentes.
4) Backup snapshot DB (pg_dump o snapshot del proveedor). Ventana de mantenimiento si cambia `max_connections` o pooler.
5) Desplegar a prod. Monitorear 60–120 min: `pg_stat_activity`, 5xx/503 rates, latencias.

### Rollback
- Revertir deployment a la versión previa; desactivar `P12_ENABLE_ADVISORY_LOCKS` si fuese necesario.
- Ningún cambio destructivo de esquema. Los cambios de pool son sólo de configuración.

### Follow-ups
- Mover insert de vistas a cola asíncrona (append-only) con batch upsert fuera de la request si el tráfico crece.
- Métricas/telemetría (OpenTelemetry): latencia de transacciones, conteo de retries, locks.
