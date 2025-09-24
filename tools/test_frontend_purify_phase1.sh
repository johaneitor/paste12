#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
if [[ -z "$BASE" ]]; then
  echo "Uso: $0 <BASE_URL>  # ej: $0 https://paste12-rmsk.onrender.com" >&2
  exit 2
fi

ts="$(date -u +%Y%m%d-%H%M%SZ)"
nocache_url="${BASE%/}/?debug=1&nosw=1&v=$(date +%s)"
tmp_html="$(mktemp)"
PASS=0; FAIL=0; WARN=0
ok(){ echo "OK  - $*"; ((PASS++))||true; }
ko(){ echo "FAIL- $*"; ((FAIL++))||true; }
wa(){ echo "WARN- $*"; ((WARN++))||true; }

# Descargar HTML live
if curl -fsS "$nocache_url" -o "$tmp_html"; then
  ok "index live descargado"
else
  ko "no se pudo descargar index ($nocache_url)"; echo "RESUMEN: PASS=$PASS FAIL=$FAIL WARN=$WARN"; exit 1
fi

# span.views
grep -qiE '<span[^>]*class="[^"]*\bviews\b' "$tmp_html" && ok "span.views" || ko "falta span.views"

# AdSense
grep -qiE 'pagead2\.googlesyndication\.com/.*/adsbygoogle\.js\?client=ca-pub-' "$tmp_html" && ok "AdSense" || wa "AdSense ausente"

# h1 duplicado (heurística)
h1c="$(grep -ioc '<h1[^>]*>' "$tmp_html" || true)"
if [[ ${h1c:-0} -le 1 ]]; then ok "encabezado único (h1)"; else wa "posible duplicado de h1 (count=$h1c)"; fi

# /terms y /privacy disponibles
code_terms="$(curl -fsS -o /dev/null -w '%{http_code}' "${BASE%/}/terms" || true)"
code_priv="$(curl -fsS -o /dev/null -w '%{http_code}' "${BASE%/}/privacy" || true)"
[[ "$code_terms" == "200" ]] && ok "terms 200" || ko "terms no devuelve 200 (http $code_terms)"
[[ "$code_priv" == "200" ]] && ok "privacy 200" || ko "privacy no devuelve 200 (http $code_priv)"

echo "RESUMEN: PASS=$PASS FAIL=$FAIL WARN=$WARN"
[[ $FAIL -eq 0 ]] || exit 1
