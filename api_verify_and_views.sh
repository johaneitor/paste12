#!/usr/bin/env bash
set -Eeuo pipefail
base="${1:-https://paste12-rmsk.onrender.com}"
ua="curl-smoke/1.0"

fetch_json () {
  local url="$1" H B
  H="$(mktemp)"; B="$(mktemp)"
  curl -sS -D "$H" -H 'Accept: application/json' -H "User-Agent: $ua" "$url" -o "$B" || true
  local scode ct; scode="$(sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p' "$H")"
  ct="$(grep -i '^content-type:' "$H" | tr -d '\r' | awk '{print tolower($0)}')"
  echo "→ $url"
  echo "  http_code=$scode  content_type=${ct#content-type: }  body_len=$(wc -c < "$B" | tr -d ' ')"
  if [[ "$scode" == "200" && "$ct" =~ application/json ]]; then
    python - "$B" <<'PY' || { echo "  ⚠️ JSON inválido. Primeros 400 bytes:"; head -c 400 "$B"; echo; }
import sys, json
with open(sys.argv[1],'rb') as f:
  d=json.load(f)
notes=d.get("notes",[])
print("  page:", d.get("page"), "page_size:", d.get("page_size"), "has_more:", d.get("has_more"))
print("  count(notes):", len(notes))
print("  ids:", [n.get("id") for n in notes][:20])
PY
  else
    echo "  ⚠️ No JSON o status != 200. Primeros 400 bytes:"
    head -c 400 "$B"; echo
  fi
  echo
  rm -f "$H" "$B"
}

pick_id () {
  local url="$1" B; B="$(mktemp)"
  curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" "$url" -o "$B" || true
  python - "$B" <<'PY' || true
import sys, json
try:
  d=json.load(open(sys.argv[1],'rb'))
  ns=d.get("notes",[])
  print(ns[0]["id"] if ns else "")
except Exception:
  print("")
PY
  rm -f "$B"
}

echo "== /api/health =="
curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" "$base/api/health"; echo; echo

echo "== GET pages =="
ts=$(date +%s) # evita caches intermedias
fetch_json "$base/api/notes?page=1&ts=$ts"
fetch_json "$base/api/notes?page=2&ts=$ts"
fetch_json "$base/api/notes?page=3&ts=$ts"

ID="$(pick_id "$base/api/notes?page=1&ts=$ts")"
echo "ID elegido = ${ID:-<vacío>}"
if [[ -z "$ID" ]]; then
  echo "⚠️ No se pudo obtener un ID (el body no fue JSON)."
  exit 0
fi

echo
echo "== POST válidos sobre note_id=$ID =="
echo "-- A #1 --"; curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" \
  -H 'X-Client-Fingerprint: user-A' -X POST "$base/api/notes/$ID/view"; echo
echo "-- A #2 (no debe contar) --"; curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" \
  -H 'X-Client-Fingerprint: user-A' -X POST "$base/api/notes/$ID/view"; echo
echo "-- B #1 --"; curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" \
  -H 'X-Client-Fingerprint: user-B' -X POST "$base/api/notes/$ID/view"; echo

echo "-- like --";   curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" -X POST "$base/api/notes/$ID/like"; echo
echo "-- report --"; curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" -X POST "$base/api/notes/$ID/report"; echo

echo
echo "== Ver contadores actuales del ID =="
curl -sS -H 'Accept: application/json' -H "User-Agent: $ua" "$base/api/notes?page=1&ts=$(date +%s)" \
| python - <<'PY'
import sys,json,os
target=os.environ.get("TARGET_ID")
d=json.load(sys.stdin)
for n in d.get("notes",[]):
  if str(n.get("id"))==target:
    print({"id":n["id"],"views":n.get("views"),"likes":n.get("likes"),"reports":n.get("reports")})
PY
echo

echo "== Fallbacks SIN id (308→400 JSON esperado) =="
curl -iL -sS -H 'Accept: application/json' -H "User-Agent: $ua" -X POST "$base/api/notes//view"   | sed -n '1,14p'
curl -iL -sS -H 'Accept: application/json' -H "User-Agent: $ua" -X POST "$base/api/notes//like"   | sed -n '1,14p'
curl -iL -sS -H 'Accept: application/json' -H "User-Agent: $ua" -X POST "$base/api/notes//report" | sed -n '1,14p'
