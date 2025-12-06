## Postmortem – view_log deadlocks y conexiones (2025-10-28)

### Timeline
- T-?d: Reportes de 5xx/503 intermitentes bajo picos.
- T0: Se detectan deadlocks en `INSERT ... ON CONFLICT DO NOTHING` sobre `view_log` y picos de conexiones.
- T0+1h: Se endurecen límites en alias `/api/view` y se prepara retry con backoff.
- T0+4h: Se añade flag de advisory locks por nota y pool parametrizable.
- T0+1d: Validación en staging, despliegue progresivo y monitoreo.

### Impacto
- Intermitente: errores 5xx/503 en vistas masivas, sin pérdida de datos confirmada.

### Causas
- Contención por índice único (hot pages) y `UPDATE notes` en la misma transacción.
- Pool no ajustado por entorno y posibles Engines adicionales.
- Rate limiting no centralizado (memoria) en despliegues multi-réplica.

### Acciones correctivas
- Backoff/retry alrededor de la transacción.
- Advisory lock opcional (flag) con `lock_timeout` bajo.
- Límite más estricto en alias legado.
- Pool SQLAlchemy configurable por env.

### Acciones preventivas
- Redis para limiter storage; pgbouncer obligatorio en producción.
- Alertas por uso de conexiones y latencia de transacciones.
- Evaluar mover writes de vistas a cola asíncrona con batch upserts.

### Lecciones
- Mantener consistencia entre endpoints legados y canónicos con límites y semántica homogénea.
- Evitar Engines múltiples en el mismo proceso.
