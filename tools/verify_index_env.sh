#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 https://host}"
TMPDIR="$(mktemp -d)"
HTML="$TMPDIR/index.html"
HTML_STATIC="$TMPDIR/static_index.html"

sep() { printf '\n== %s ==\n' "$*"; }

sep "HEADERS /"
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|x-wsgi-bridge:|cache-control:|cf-cache-status:|age:|server:)/{print}'

sep "DESCARGA /"
curl -sL "$BASE/" -o "$HTML"
bytes=$(wc -c <"$HTML" | tr -d ' ')
printf 'Tamaño: %s bytes\n' "$bytes"
if command -v sha256sum >/dev/null 2>&1; then
  sha=$(sha256sum "$HTML" | awk '{print $1}')
  printf 'SHA256: %s\n' "$sha"
fi

sep "PASTEL TOKEN en /"
if grep -qm1 -- '--teal:#8fd3d0' "$HTML"; then
  echo "OK pastel (token presente)"
else
  echo "NO pastel (token ausente)"
fi

sep "UI nueva (menu ⋯ + Compartir/Reportar)"
ui_ok=1
grep -qm1 'class="act more"' "$HTML" || ui_ok=0
grep -qm1 'class="menu' "$HTML"      || ui_ok=0
grep -qm1 'class="share"' "$HTML"    || ui_ok=0
grep -qm1 'class="report"' "$HTML"   || ui_ok=0
if [ "$ui_ok" -eq 1 ]; then
  echo "OK UI nueva detectada"
else
  echo "NO se detecta UI nueva"
fi

sep "NO-STORE en /"
if curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^cache-control:/{print}' | grep -qi 'no-store'; then
  echo "OK no-store presente"
else
  echo "NO no-store"
fi

sep "¿/static/index.html existe?"
code=$(curl -sI "$BASE/static/index.html" | awk 'NR==1{print $2}')
echo "HTTP $code"
if [ "$code" = "200" ]; then
  curl -sL "$BASE/static/index.html" -o "$HTML_STATIC"
  if command -v sha256sum >/dev/null 2>&1; then
    sha2=$(sha256sum "$HTML_STATIC" | awk '{print $1}')
    echo "SHA256 /static/index.html: $sha2"
  fi
  if grep -qm1 -- '--teal:#8fd3d0' "$HTML_STATIC"; then
    echo "Token pastel en /static/index.html: OK"
  else
    echo "Token pastel en /static/index.html: NO"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    if [ "${sha:-x}" = "${sha2:-y}" ]; then
      echo "/ y /static/index.html coinciden (mismo archivo)"
    else
      echo "/ y /static/index.html SON DISTINTOS (posible handler raíz distinto)"
    fi
  fi
fi

sep "DUPLICADOS Términos/Privacidad (en /)"
t=$(grep -oi 'términos' "$HTML"    | wc -l | tr -d ' ')
p=$(grep -oi 'privacidad' "$HTML"  | wc -l | tr -d ' ')
echo "Ocurrencias: Términos=$t Privacidad=$p (>=2 puede indicar duplicado)"

sep "DIAGNÓSTICO /api/health (si hay JSON)"
if command -v jq >/dev/null 2>&1 && curl -sf "$BASE/api/health" >/dev/null; then
  curl -s "$BASE/api/health" | jq '{static_folder:.["app.static_folder"], has_index_html:.["index.html"], routes_count:(.routes|length)}' 2>/dev/null || true
else
  echo "Sin JSON legible o jq no disponible"
fi

sep "CONCLUSIÓN"
echo "Si NO hay pastel en / pero SÍ en /static/index.html => la app base está sirviendo otra raíz."
echo "Si falta no-store en / => añadir sólo en esa respuesta para evitar caché."
