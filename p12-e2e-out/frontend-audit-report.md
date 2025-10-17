# Paste12 – Auditoría E2E de Frontend (Remota)

Fecha: 2025-10-17
Destino: `https://paste12-rmsk.onrender.com`
Repo: `github.com/johaneitor/paste12`

---

## 1) Preparación
- Objetivo: Verificar entorno y preparar herramientas de auditoría.
- Comandos ejecutados:
  - `node -v`, `npm -v`, `curl --version`, `jq --version`
  - `npm i -D puppeteer axe-core`
- Resultado: PASS
- Evidencia: `p12-e2e-out/scripts/*`
- Gravedad: LOW
- Diagnóstico: Entorno listo.
- Reparación sugerida: N/A
- PR/branch creado: N/A

## 2) Smoke test visual básico
- Objetivo: Cargar `/` y `/notes` y verificar errores.
- Comandos ejecutados:
  - `node p12-e2e-out/scripts/smoke.mjs https://paste12-rmsk.onrender.com /`
  - `node p12-e2e-out/scripts/smoke.mjs https://paste12-rmsk.onrender.com /notes`
- Resultado: PARTIAL PASS
- Evidencia: `p12-e2e-out/*/remote-smoke/result.json`, `screenshot.png`
- Gravedad: MEDIUM (ruta `/notes` responde 404)
- Diagnóstico: `/` rinde <1.3s, sin errores JS. `/notes` devuelve 404.
- Reparación sugerida: Redirigir `/notes` a `/` o servir plantilla de listado.
- PR/branch: pendiente

## 3) Integridad de assets y compilación
- Objetivo: Validar carga y cache de `app.js`/`styles.css`.
- Comandos: `curl -I /js/app.js`, `curl -I /css/styles.css`
- Resultado: PASS (sirve con `content-encoding: br`), pero `cache-control: no-cache`.
- Evidencia: headers en reporte.
- Gravedad: LOW
- Diagnóstico: Compresión OK; cache mejorable.
- Reparación: Cambiar a `public, max-age=604800, immutable` en assets versionados.

## 4) Funcionalidad JS / UX
- Objetivo: Comprobar CRUD superficial.
- Comandos: `curl -X POST /api/notes` (crear), luego GET.
- Resultado: PARTIAL PASS (crear OK; like/report fallan 500 remoto).
- Evidencia: respuestas 500 en like/report.
- Gravedad: MEDIUM
- Diagnóstico: Backend retorna 500; UI muestra error y no rompe.
- Reparación: Corregir endpoints `/api/notes/:id/like|report` en backend.

## 5) Seguridad cliente (XSS / DOM / CORS)
- Objetivo: Probar entradas peligrosas.
- Comandos: POST con `<b>negrita</b>`; render usa `esc()`.
- Resultado: PASS (escape en cliente); CORS `*` en `/api/notes`.
- Evidencia: `backend/frontend/js/app.js` usa `esc(n.text)`.
- Gravedad: MEDIUM (CSP permite Ads scripts; evaluar).
- Diagnóstico: CSP presente; falta headers `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy` en raíz pública.
- Reparación: Asegurar estos headers a nivel WSGI/Flask para vistas públicas.

## 6) Accesibilidad (A11y)
- Objetivo: Axe/Lighthouse.
- Comandos: (axe no corrió por limitación), revisión manual + reporte HTML.
- Resultado: PARTIAL PASS
- Evidencia: `p12-e2e-out/a11y-report.html`
- Gravedad: LOW
- Diagnóstico: Semántica básica OK; mejorar `:focus` y `aria-live`.
- Reparación: Añadir estilos de foco y estados live.

## 7) Rendimiento
- Objetivo: Lighthouse + métricas básicas.
- Comandos: `smoke.mjs` timings.
- Resultado: PASS
- Evidencia: DOMContentLoaded ~320ms; bundle js ~3.4KB br.
- Gravedad: LOW
- Diagnóstico: Ligero y rápido.
- Reparación: Opcional: `preload` crítico, `immutable` cache.

## 8) SEO y meta-tags
- Objetivo: Validar `<title>`, description, og, favicon, canonical.
- Resultado: FAIL parcial
- Evidencia: `backend/frontend/index.html` sin `meta description`, OG/Twitter, canonical.
- Gravedad: MEDIUM
- Reparación: Añadir metas SEO básicas y OG.

## 9) i18n
- Objetivo: Idioma y textos.
- Resultado: PASS parcial
- Evidencia: `lang="es"` en páginas legales; UI en español.
- Gravedad: LOW
- Reparación: Declarar `lang="es"` en `index.html` y considerar estructura i18n futura.

## 10) Integración con backend
- Objetivo: Comprobar fetch y manejo de errores.
- Resultado: PARTIAL PASS
- Evidencia: GET notas OK; like/report 500.
- Gravedad: MEDIUM
- Reparación: Fix backend.

## 11) Cache, compresión y CDN
- Objetivo: gzip/br y cache headers.
- Resultado: PASS parcial
- Evidencia: `content-encoding: br`; `cf-cache-status: DYNAMIC`; `cache-control: no-cache` (assets).
- Gravedad: LOW
- Reparación: Cache assets estáticos con `public, max-age=604800, immutable`.

## 12) Reporte y correcciones
- Hallazgos clave:
  1. `/notes` 404 – MEDIUM
  2. Like/Report 500 – MEDIUM
  3. Falta metas SEO – MEDIUM
  4. Headers de seguridad ausentes en raíz – MEDIUM
  5. Cache-Control mejorable en assets – LOW

- Correcciones sugeridas (frontend):
  - Añadir metas SEO y `lang` en `backend/frontend/index.html`.
  - Forzar headers de seguridad en `backend/__init__.py` para rutas front.
  - Ajustar `Cache-Control` para `/css/*` y `/js/*` (ya hay after_request, revisar valores).

- PR/branch: pendiente

---

## Evidencia clave
- `p12-e2e-out/2025-10-17T02-59-05-786Z/remote-smoke/result.json`
- `p12-e2e-out/2025-10-17T02-59-05-786Z/remote-smoke/root.html`
- `p12-e2e-out/a11y-report.html`

---

## Resumen ejecutivo
- Top 10 hallazgos:
  - `/notes` 404 (MEDIUM)
  - Like/Report 500 (MEDIUM)
  - Sin `meta description`/OG/Twitter (MEDIUM)
  - Falta `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy` en raíz (MEDIUM)
  - Cache-Control de assets como `no-cache` (LOW)
  - A11y: foco y `aria-live` (LOW)
  - CSP presente pero permisiva para Ads (LOW–MEDIUM)
  - CORS `*` en `/api/notes` (MEDIUM, revisar contexto)
  - SEO: sin canonical (LOW)
  - i18n: declarar `lang` en `index.html` (LOW)

- Recomendaciones:
  - Redirigir `/notes` → `/` y servir listados.
  - Arreglar endpoints de like/report.
  - Añadir metas SEO/OG y `lang`.
  - Asegurar headers de seguridad desde Flask para todas las rutas HTML y estáticos.
  - Poner cache agresiva en assets versionados.

- Checklist de fixes aplicados: N/A (auditoría remota).
