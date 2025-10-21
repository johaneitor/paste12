# Frontend E2E Audit Report

App: paste12 (BASE_URL: https://paste12-rmsk.onrender.com)
Date: 2025-10-21
Scope: Visual smoke, accessibility, performance, client security, FE/API consistency. Non-destructive.

## 1) Smoke visual (no destructivo)
- Objetivo: Cargar `/` y `/notes` bloqueando métodos mutadores a `/api/*` y registrar errores, timings y red.
- Comandos: `node p12-audit/smoke.mjs "https://paste12-rmsk.onrender.com"`
- Resultado: PASS
- Evidencia: `./audit-out/puppeteer-smoke.json`, `./audit-out/puppeteer-smoke.txt`
- Métricas clave:
  - `/` DCL≈740ms, sin errores JS.
  - `/notes` DCL≈304ms, sin errores JS.
- Gravedad: LOW
- Diagnóstico: Navegación saludable y tiempos aceptables. Se observan múltiples POST `/api/notes/{id}/view` en sesiones previas (ver artefactos históricos), a vigilar.
- Reparación sugerida: Asegurar disparo único por tarjeta (IntersectionObserver + guardas en `sessionStorage`).

## 2) Integridad de assets y headers
- Objetivo: Validar Cache-Control, ETag/Last-Modified, Content-Encoding y cabeceras de seguridad.
- Comandos (resumen): curl -I/ -D - a `/`, `/notes`, `/assets/*.js|.css`, `/favicon.ico`, `/api/health`.
- Resultado: MIXED
- Evidencia: `./audit-out/headers_root.txt`, `headers_notes.txt`, `headers__assets_*.txt`, `headers__favicon.ico.txt`, `headers_health.txt`, `encoding__assets_*.txt`.
- Hallazgos:
  - HTML: `Cache-Control: no-store` (OK para HTML dinámico).
  - Assets: responden con `content-type: text/html` bajo rutas `/assets/*.js|.css` (probable fallback del server). Compresión `br` presente pero el content-type es incorrecto → rompe caching y seguridad (nosniff ayuda pero browsers dependen del tipo).
  - Seguridad: `HSTS`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` (todos presentes, OK).
  - CSP en headers con `frame-ancestors 'self'` (correcto; no en `<meta>`).
  - Favicon con `Cache-Control: no-cache` (mejorable; debería ser cacheable con hash y `immutable`).
- Gravedad: HIGH
- Reparación sugerida:
  - Corregir routing estático para servir `*.js` como `application/javascript` y `*.css` como `text/css` con `Cache-Control: public, max-age=31536000, immutable` y ETag.
  - Mantener HTML como `no-store`. Confirmar CDN (`cf-cache-status`) y habilitar HIT en assets.

## 3) Seguridad cliente (XSS / CORS)
- Objetivo: Validar escape de HTML pasivo y CORS.
- Comandos: `curl -i -X OPTIONS /api/notes` con `Origin: https://evil.example`.
- Resultado: PASS (CORS preflight controlado)
- Evidencia: `./audit-out/cors_options_notes.txt`
- Hallazgos:
  - ACAO refleja el origen solicitado (Vary: Origin) solo para OPTIONS. Revisar políticas para métodos GET/POST según requerimientos.
  - CSP estricta, pero permite dominios de ads en `script/img/frame-src`.
- Gravedad: MEDIUM
- Reparación sugerida: Limitar CORS a orígenes conocidos o usar wildcard solo cuando proceda; evaluar Trusted Types y reducir superficie de ads si no es crítica.

## 4) Accesibilidad (A11y)
- Objetivo: Generar reporte Lighthouse de accesibilidad.
- Comandos: `npx lighthouse --only-categories=accessibility`.
- Resultado: PASS (reporte generado)
- Evidencia: `./audit-out/a11y-report.html`
- Hallazgos principales: Sin errores críticos a nivel de estructura; revisar detalles en el reporte.
- Gravedad: LOW
- Reparación sugerida: Atender observaciones de contraste, nombres accesibles e hit targets si aparecen en el reporte.

## 5) Rendimiento
- Objetivo: Medir performance/seo/best-practices y aislar impacto de ads.
- Comandos: Lighthouse estándar y variante con dominios de ads bloqueados.
- Resultado: MIXED
- Evidencia: `./audit-out/lh-report.html`, `./audit-out/lh-report.report.json`, `./audit-out/lh-report-block-ads.*`
- Hallazgos:
  - Compresión `br` activa.
  - JS/CSS no cacheables por content-type incorrecto; impacto directo en LCP/TBT/TTI y en CDN HIT.
  - Ads cargan iframes y requests de `googlesyndication/doubleclick`; la variante bloqueada mejora métricas (ver reporte).
- Gravedad: HIGH
- Reparación sugerida:
  - Corregir tipos MIME y caching de assets fingerprinted.
  - Postergar/condicionar carga de anuncios (consent, lazy, tamaño fijo para CLS).

## 6) SEO/meta
- Objetivo: Verificar `<title>`, meta description, OG y canonical.
- Evidencia: `./audit-out/seo-snapshot.html`
- Resultado: PASS con mejoras
- Hallazgos: `title`, `meta description`, `og:title/description/image`, `canonical`, `favicon` presentes.
- Gravedad: LOW
- Reparación sugerida: Añadir `og:url` y `twitter:card`, `twitter:title/description/image`; asegurar favicon multi-formato (`.ico`/`.svg`).

## 7) i18n
- Observación: UI en español consistente. No se detectan mezclas notorias en home. Revisar `/notes` para listados.
- Gravedad: LOW
- Reparación sugerida: Centralizar strings y exponer mecanismo de localización si se planea multilengua.

## 8) Integración con backend
- Objetivo: Validar GET `/api/notes` y manejo de estado.
- Evidencia: `puppeteer-smoke.json` muestra `status: 200` en fetch inicial; no se observaron 4xx en `/notes`.
- Gravedad: MEDIUM
- Reparación sugerida: Implementar paginación explícita (Link headers o `X-Total-Count`) y estados de loading/error visibles.

## 9) Cache/Compresión/CDN
- Hallazgos: `cf-cache-status: DYNAMIC` en HTML y assets → CDN no está cacheando assets (tipos erróneos). `Content-Encoding: br` OK.
- Gravedad: HIGH
- Reparación sugerida: Corregir MIME y `Cache-Control` de assets, habilitar `ETag/Last-Modified`; esperar `HIT` en CDN.

## 10) Interacciones infladas
- Observación: Históricos muestran múltiples POST `/api/notes/{id}/view` por sesión y por item (ver artefactos previos). No se dispararon en la corrida actual por bloqueo de métodos.
- Gravedad: MEDIUM
- Reparación sugerida: Guardas de vista única por ítem (IntersectionObserver + marca `sessionStorage` por `noteId`), idempotencia en BE y rate-limit suave por FP.

---

## Top 10 hallazgos por severidad
1. Assets `*.js|*.css` servidos con `content-type: text/html` (HIGH)
2. CDN sin HIT en assets por tipos/caching (HIGH)
3. Carga de anuncios impacta performance (HIGH)
4. Favicon no cacheable (MEDIUM)
5. CORS refleja origen en preflight; validar políticas (MEDIUM)
6. Falta de paginación/headers estándar en `/api/notes` (MEDIUM)
7. Posibles vistas duplicadas `/view` por ítem (MEDIUM)
8. Falta `og:url`/`twitter:*` (LOW)
9. Oportunidades menores de a11y (LOW)
10. Consolidar i18n (LOW)

## Recomendaciones concretas
- Backend/serving:
  - Mapear `*.js → application/javascript`, `*.css → text/css`, `*.svg → image/svg+xml`.
  - `Cache-Control` assets fingerprinted: `public, max-age=31536000, immutable`.
  - HTML: `no-store` (mantener). Favicon: `public, max-age=604800` o fingerprint.
  - Verificar `ETag` fuerte y `Last-Modified`.
- Performance:
  - Lazy-load y/o consentimiento para anuncios; reservar espacio para evitar CLS.
  - Modern bundle y tree-shaking; medir LCP/TBT tras fixes.
- Seguridad:
  - Mantener CSP en headers; evaluar Trusted Types si hay DOM sinks.
  - Revisar CORS para métodos sensibles.
- UX/SEO:
  - Añadir `og:url`, `twitter:card`/meta; verificar `rel=canonical` absoluto.
- FE/BE:
  - Paginación y `X-Total-Count` o `Link` headers; estados de carga/errores claros.
- Interacciones:
  - Un solo POST `/view` por ítem con guardas; idempotencia y rate-limit en BE.

## Artefactos
- `./audit-out/puppeteer-smoke.json`
- `./audit-out/puppeteer-smoke.txt`
- `./audit-out/headers_root.txt`
- `./audit-out/headers_notes.txt`
- `./audit-out/headers__assets_index-*.js.txt`
- `./audit-out/headers__assets_*.css.txt`
- `./audit-out/headers__favicon.ico.txt`
- `./audit-out/headers_health.txt`
- `./audit-out/encoding__assets_index-*.js.txt`
- `./audit-out/encoding__assets_*.css.txt`
- `./audit-out/a11y-report.html`
- `./audit-out/lh-report.html`
- `./audit-out/lh-report.report.json`
- `./audit-out/lh-report-block-ads.report.html`
- `./audit-out/lh-report-block-ads.report.json`
- `./audit-out/seo-snapshot.html`
- `./audit-out/frontend-audit-report.md`

## Notas y restricciones
- No se mutaron datos; Puppeteer bloqueó POST/PUT/PATCH/DELETE a `/api/*`.
- Sin secretos expuestos; variables no sensibles redaccionadas.
- Concurrencia baja para evitar carga excesiva.
