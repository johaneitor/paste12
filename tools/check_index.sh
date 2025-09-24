#!/usr/bin/env bash
# Uso: tools/check_index.sh https://tu-dominio
set -euo pipefail
BASE="${1:-${BASE:-}}"
[ -n "${BASE}" ] || { echo "Uso: $0 <base-url>"; exit 2; }

fail(){ echo "✗ $1"; exit 1; }
ok(){ echo "✓ $1"; }

# HEAD /
hdr="$(curl -sI "$BASE/")" || fail "curl HEAD / falló"
code="$(printf "%s" "$hdr" | awk 'NR==1{print $2}')"
[ "$code" = "200" ] || fail "/ devolvió $code"
echo "$hdr" | grep -qi '^x-wsgi-bridge:' || fail "falta header X-WSGI-Bridge"
echo "$hdr" | grep -qi '^cache-control:.*no-store' || fail "falta Cache-Control no-store"

# GET /
html="$(curl -s "$BASE/")" || fail "curl GET / falló"
echo "$html" | grep -q -- '--teal:#8fd3d0' || fail "no encontré token pastel (--teal:#8fd3d0)"
echo "$html" | grep -Eq 'id="send"[^>]*>|class="btn"[^>]*>[^<]*Publicar' || fail "no encontré botón Publicar"
echo "$html" | grep -q 'textarea[^>]*id="text"' || fail "no encontré textarea #text"

ok "index pastel OK"
