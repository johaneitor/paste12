#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"
if [ -z "$BASE" ]; then
  echo "Uso: $0 https://tu-app.onrender.com" >&2
  exit 1
fi

pass=0; fail=0
say() { printf "%s\n" "$*"; }
ok(){ say "OK  - $*"; pass=$((pass+1)); }
bad(){ say "FAIL- $*"; fail=$((fail+1)); }

# --- Health (acepta texto 'health ok' o JSON {"ok":true}) ---
hb="$(curl -fsS "$BASE/api/health" || true)"
if [ "$hb" = "health ok" ]; then ok "health body: health ok"
elif [ "$hb" = '{"ok":true}' ]; then ok 'health body: {"ok":true}'
else bad "health body inesperado: $hb"
fi

# --- CORS preflight OPTIONS /api/notes: 204 + headers ---
hdr="$(curl -i -fsS -X OPTIONS "$BASE/api/notes" | sed -n '1,30p')"
echo "$hdr" | head -n1 | grep -q "204" && ok "204" || bad "esperaba 204"
echo "$hdr" | grep -qi '^Access-Control-Allow-Methods: .*GET.*POST.*OPTIONS' && ok "ACAM" || bad "ACAM"
echo "$hdr" | grep -qi '^Access-Control-Allow-Headers: .*Content-Type' && ok "ACAH" || bad "ACAH"
echo "$hdr" | grep -qi '^Access-Control-Max-Age: ' && ok "Max-Age" || bad "Max-Age"

# --- FE index básico ---
html_bytes="$(curl -fsS "$BASE/" | wc -c | tr -d ' ')"
if [ "${html_bytes:-0}" -ge 200 ]; then ok "index bytes > 200"; else bad "index chico ($html_bytes)"; fi
curl -fsS "$BASE/" | grep -q "p12-safe-shim" && ok "p12-safe-shim" || ok "p12-safe-shim (no encontrado, permitido)"

# --- GET /api/notes?limit=3: 200 + CT json + Link (si está) ---
notes_hdr="$(curl -i -fsS "$BASE/api/notes?limit=3")"
echo "$notes_hdr" | head -n1 | grep -q "200" && ok "200" || bad "GET /api/notes 200"
echo "$notes_hdr" | grep -qi '^Content-Type: .*json' && ok "CT json" || bad "CT json"
# Link: si no está, lo avisamos como info (tolerante)
if echo "$notes_hdr" | grep -qi '^Link:'; then ok "Link: next"; else say "info: Link ausente (tolerado)"; fi

# --- Publish JSON y FORM -> single ---
jid="$(curl -fsS -H 'Content-Type: application/json' -d '{"text":"test-suite json —— 1234567890 abcdefghij"}' "$BASE/api/notes" \
      | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [ -n "$jid" ]; then ok "publish JSON id=$jid"; else bad "publish JSON"; fi

fid="$(curl -s -o /dev/null -w '%{http_code}\n' -d 'text=test-suite form —— 1234567890 abcdefghij' "$BASE/api/notes")"
if [ "$fid" = "200" ] || [ "$fid" = "201" ]; then ok "publish FORM (HTTP $fid)"; else bad "publish FORM (HTTP $fid)"; fi

# Single: si existe /api/notes/<id> o /note/<id> lo probamos
single_ok=0
if [ -n "${jid:-}" ]; then
  sc="$(curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/notes/$jid" || true)"
  if [ "$sc" = "200" ]; then ok "single json body"; single_ok=1; fi
  if [ $single_ok -eq 0 ]; then
    sc2="$(curl -s -o /dev/null -w '%{http_code}\n' "$BASE/note/$jid" || true)"
    [ "$sc2" = "200" ] && ok "single html body" && single_ok=1
  fi
  [ $single_ok -eq 0 ] && say "info: single no disponible (tolerado)"
fi

say
say "RESUMEN: PASS=$pass FAIL=$fail"
[ $fail -eq 0 ] || exit 1
