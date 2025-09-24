#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }

echo "== HEADERS / =="
curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^(HTTP\/|cache-control:|x-(index-source|wsgi-bridge):)/{print}'
hr

HTML="$(curl -fsS "$BASE/")"
rot_count="$(printf "%s" "$HTML" | grep -io '<h2[^>]*id="tagline-rot"[^>]*>' | wc -l | awk '{print $1}')"
fixed_count="$(printf "%s" "$HTML" | grep -io '<div[^>]*id="tagline"[^>]*>' | wc -l | awk '{print $1}')"
marker_count="$(printf "%s" "$HTML" | grep -c '<!-- TAGLINE-ROTATOR -->' || true)"

echo "== TAGLINE AUDIT =="
[ "$rot_count" = "1" ] && ok "hay 1 rotador (h2#tagline-rot)" || bad "rotadores: $rot_count (debe ser 1)"
[ "$fixed_count" = "0" ] && ok "sin <div id=\"tagline\"> fijos" || bad "taglines fijos: $fixed_count (sobran)"
[ "$marker_count" -ge 1 ] && ok "script rotador presente" || bad "script rotador ausente"

# Muestra contexto si hay duplicados
if [ "$rot_count" != "1" ] || [ "$fixed_count" != "0" ]; then
  echo "-- Contexto (coincidencias) --"
  printf "%s" "$HTML" | nl -ba | grep -niE 'tagline-rot|id="tagline"' | sed -n '1,120p'
fi
hr

echo "== BRAND COLOR =="
# pasa si: (clase brand-gradient) o (h1.brand tiene linear-gradient)
has_class="$(printf "%s" "$HTML" | grep -qi 'class="[^"]*\bbrand-gradient\b' && echo 1 || echo 0)"
has_grad="$(printf "%s" "$HTML" | grep -qi '<h1[^>]*class="[^"]*\bbrand\b[^"]*"[^>]*style="[^"]*linear-gradient' && echo 1 || echo 0)"
if [ "$has_class" = 1 ] || [ "$has_grad" = 1 ]; then ok "brand con degradado"; else bad "brand sin degradado detectado"; fi

# heurística de colores: verde-azulado + naranja en CSS
has_teal="$(printf "%s" "$HTML" | grep -qiE '#14b8a6|#0fb|#008080|#8fd3d0' && echo 1 || echo 0)"
has_orng="$(printf "%s" "$HTML" | grep -qiE '#f97316|#ff8a00|#ff9a3c|#ffb38a' && echo 1 || echo 0)"
if [ "$has_teal" = 1 ] && [ "$has_orng" = 1 ]; then ok "paleta teal+naranja detectada"; else bad "no se detectó teal+naranja"; fi

hr
echo "RESUMEN: ok=$pass, fail=$fail"
[ $fail -eq 0 ] || exit 1
