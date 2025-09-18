# Test suite Paste12

## Runner principal
- `tools/test_suite_all.sh https://host`
  - Health
  - CORS (OPTIONS /api/notes)
  - Index sin SW (+ tamaño, marcador p12-safe-shim)
  - Paginación (Link rel="next", Content-Type JSON)
  - Publish JSON + FORM (201 + id)
  - Like/View
  - Single (meta o body)
  - HEAD/headers (info)

## Negativos / sanity
- `tools/test_suite_negative.sh https://host`
  - Inputs vacíos (JSON/FORM)
  - Ids inexistentes (like/view)
  - Método no permitido
  - CORS simple GET

## Recomendado dejar sólo:
- `trace_fe_be_v3.sh` (para sesiones de diagnóstico manual)
- `smoke_ui_like_view_share_v4.sh` (smoke UI rápido)
- `audit_frontend_to_sdcard_v2.sh` (dump local/SD)
- `test_suite_all.sh` + `test_suite_negative.sh`

Eliminar (si existen): `trace_fe_be.sh`, `trace_fe_be_v2.sh`, `smoke_ui_like_view_share_v3.sh`, `audit_frontend_to_sdcard.sh`
