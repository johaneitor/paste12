#!/usr/bin/env bash
set -Eeuo pipefail
base="${1:-https://paste12-rmsk.onrender.com}"

fetch_json () {
  local url="$1" tag="$2"
  local H B; H="$(mktemp)"; B="$(mktemp)"
  curl -sS -D "$H" -H 'Accept: application/json' "$url" -o "$B" || true
  local scode ct blen
  scode="$(sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p' "$H")"
  ct="$(grep -i '^content-type:' "$H" | tr -d '\r' | awk '{print tolower($0)}')"
  blen="$(wc -c < "$B" | tr -d ' ')"
  echo "→ $url"
  echo "  http_code=$scode  content_type=${ct#content-type: }  body_len=$blen"

  if [[ "$scode" == "200" && "$ct" =~ application/json ]]; then
    python - <<PY < "$B" || { echo "  ⚠️ JSON inválido. Primeros 400 bytes:"; head -c 400 "$B"; echo; }
import sys, json
d=json.load(sys.stdin)
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

echo "== /api/health =="
curl -sS -H 'Accept: application/json' "$base/api/health"; echo; echo

echo "== GET pages =="
fetch_json "$base/api/notes?page=1" "p1"
fetch_json "$base/api/notes?page=2" "p2"
fetch_json "$base/api/notes?page=3" "p3"

# Extraer primer ID de page=1 sin archivos intermedios
ID="$(
  curl -sS -H 'Accept: application/json' "$base/api/notes?page=1" \
  | python - <<'PY'
import sys,json
try:
  d=json.load(sys.stdin); ns=d.get("notes",[])
  print(ns[0]["id"] if ns else "")
except Exception: print("")
PY
)"
echo "ID elegido = ${ID:-<vacío>}"
if [[ -n "$ID" ]]; then
  echo
  echo "== POST válidos sobre note_id=$ID =="
  echo "-- view   ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/view";   echo
  echo "-- like   ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/like";   echo
  echo "-- report ->";  curl -sS -H 'Accept: application/json' -X POST "$base/api/notes/$ID/report"; echo
fi

echo
echo "== Fallbacks SIN id (308→400 JSON esperado) =="
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//view"   | sed -n '1,12p'
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//like"   | sed -n '1,12p'
curl -iL -sS -H 'Accept: application/json' -X POST "$base/api/notes//report" | sed -n '1,12p'
