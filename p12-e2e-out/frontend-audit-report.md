# Paste12 Frontend E2E Audit

Fecha: 2025-10-20T18:42Z
Objetivo: Auditoría visual, accesibilidad, rendimiento, seguridad y consistencia FE/API

## 1) Smoke test visual
- URL: https://paste12-rmsk.onrender.com/
- Resultado: PASS (200)
- Tiempos:
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:27:10 GMT
  content-type: text/html; charset=utf-8
  cache-control: no-store

## 2) /notes
- URL: https://paste12-rmsk.onrender.com/notes
- Resultado: FAIL (404)

## 3) Assets
- /js/app.js: headers
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:29:55 GMT
  content-type: text/javascript; charset=utf-8
  cache-control: no-cache
  content-disposition: inline; filename=app.js
  etag: W/"1760983748.0-11441-3782283996"
  last-modified: Mon, 20 Oct 2025 18:09:08 GMT
  referrer-policy: no-referrer
  rndr-id: 11682711-12bd-44f4
  strict-transport-security: max-age=31536000; includeSubDomains; preload
  vary: Accept-Encoding
  x-content-type-options: nosniff
  x-frame-options: DENY
  x-render-origin-server: gunicorn
  cf-cache-status: DYNAMIC
  server: cloudflare
  cf-ray: 991a955b8c314652-CMH
  alt-svc: h3=":443"; ma=86400
  
- /css/styles.css: headers
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:29:57 GMT
  content-type: text/css; charset=utf-8
  cache-control: no-cache
  content-disposition: inline; filename=styles.css
  etag: W/"1760983748.0-3196-1212224791"
  last-modified: Mon, 20 Oct 2025 18:09:08 GMT
  referrer-policy: no-referrer
  rndr-id: 080818be-e201-46a6
  strict-transport-security: max-age=31536000; includeSubDomains; preload
  vary: Accept-Encoding
  x-content-type-options: nosniff
  x-frame-options: DENY
  x-render-origin-server: gunicorn
  cf-cache-status: DYNAMIC
  server: cloudflare
  cf-ray: 991a9566c98a77be-CMH
  alt-svc: h3=":443"; ma=86400
  

## 4) Seguridad del cliente
- Headers /: 
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:33:13 GMT
  content-type: text/html; charset=utf-8
  cache-control: no-store
  referrer-policy: no-referrer
  rndr-id: 819ca829-0631-4d3b
  strict-transport-security: max-age=31536000; includeSubDomains; preload
  vary: Accept-Encoding
  x-content-type-options: nosniff
  x-frame-options: DENY
  x-render-origin-server: gunicorn
  cf-cache-status: DYNAMIC
  server: cloudflare
  cf-ray: 991a9a345ccc5751-CMH
  alt-svc: h3=":443"; ma=86400
  
- CORS (OPTIONS /api/notes):
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:27:15 GMT
  content-type: text/html; charset=utf-8
  access-control-allow-headers: Content-Type
  access-control-allow-methods: DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT
  access-control-allow-origin: https://example.com
  allow: OPTIONS, POST, HEAD, GET
  referrer-policy: no-referrer
  rndr-id: 2632d475-fc4b-4d2c
  strict-transport-security: max-age=31536000; includeSubDomains; preload
  vary: Origin
  vary: Accept-Encoding
  x-content-type-options: nosniff
  x-frame-options: DENY
  x-render-origin-server: gunicorn
  cf-cache-status: DYNAMIC
  server: cloudflare
  cf-ray: 991a91714f001709-CMH
  alt-svc: h3=":443"; ma=86400
  

## 5) API
- GET /api/notes → 200, Link rel=next
  HTTP/2 200 
  date: Mon, 20 Oct 2025 18:27:13 GMT
  content-type: application/json
  access-control-allow-origin: *
  link: <https://paste12-rmsk.onrender.com/api/notes?limit=20&before_id=688>; rel="next"
  referrer-policy: no-referrer
  rndr-id: 0c25beac-298f-4ce6
  strict-transport-security: max-age=31536000; includeSubDomains; preload
  vary: Accept-Encoding
  x-content-type-options: nosniff
  x-frame-options: DENY
  x-render-origin-server: gunicorn
  cf-cache-status: DYNAMIC
  server: cloudflare
  cf-ray: 991a91644e20f41a-CMH
  alt-svc: h3=":443"; ma=86400
  

## 6) SEO/meta (home)

- Título/descripción/OG/canonical: presentes.
- CSP ahora recomendado por header (no por meta) para habilitar frame-ancestors.


## 7) A11y semántica (rápida)

- Reporte generado en ./p12-e2e-out/a11y-report.html


## 8) XSS pasivo (contenido)
- Evidencia: /api/notes incluye '<script>' en texto (no se ejecuta por escape en FE).

## 9) Compresión/CDN
- Brotli activo en HTML; CF DYNAMIC; JS/CSS no-cache; ETag presente.

## 10) Cambios propuestos (FE/BE)

- front_bp: Cache-Control public, max-age=604800, immutable para /css, /js, /img.
- front_bp: redirect 302 de /notes a /.
- backend/__init__.py: emitir CSP por header para HTML.
- frontend/index.html: reducir CSP en meta (informativo); header manda.
