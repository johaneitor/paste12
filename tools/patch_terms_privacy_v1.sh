#!/usr/bin/env bash
set -euo pipefail
mkdir -p backend/static
cat > backend/static/terms.html <<'H'
<!doctype html><meta charset="utf-8">
<meta http-equiv="cache-control" content="no-store">
<title>Términos de Servicio — paste12</title>
<h1>Términos de Servicio</h1>
<p>Uso aceptable; no spam ni scraping abusivo; contenido ilegal será removido;
las notas pueden expirar o podarse por capacidad.</p>
H
cat > backend/static/privacy.html <<'H'
<!doctype html><meta charset="utf-8">
<meta http-equiv="cache-control" content="no-store">
<title>Privacidad — paste12</title>
<h1>Política de Privacidad</h1>
<p>Guardamos metadatos mínimos para operar (p.ej. cookie anónima p12uid).
Datos de auditoría anti-abuso se usan sólo para proteger la plataforma.</p>
H
echo "OK: /terms y /privacy escritos en backend/static"
