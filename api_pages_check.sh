#!/usr/bin/env bash
set -Eeuo pipefail
base="https://paste12-rmsk.onrender.com"

check() {
  p="$1"
  echo "== GET /api/notes?page=$p =="
  curl -sS -D "/tmp/hn$p" -H 'Accept: application/json' "$base/api/notes?page=$p" -o "/tmp/bn$p" || true
  echo "--- HEADERS $p ---"; sed -n '1,20p' "/tmp/hn$p" || true
  scode=$(sed -n '1s/.* \([0-9][0-9][0-9]\).*/\1/p' "/tmp/hn$p")
  echo "--- STATUS: $scode ---"
  if [[ "$scode" != "200" ]]; then
    echo "Body (primeros 300 bytes):"; head -c 300 "/tmp/bn$p"; echo; echo
    return
  fi
  python - <<PY || { echo "⚠️  No es JSON válido (p=$p). Primeros 300 bytes:"; head -c 300 "/tmp/bn$p"; echo; }
import json,sys; d=json.load(open("/tmp/bn$p"))
ns=d.get("notes",[])
print("page:", d.get("page"), "page_size:", d.get("page_size"), "has_more:", d.get("has_more"))
print("count:", len(ns), "ids:", [n["id"] for n in ns])
PY
  echo
}

check 1
check 2

if [[ -f /tmp/bn1 && -f /tmp/bn2 ]]; then
  python - <<'PY'
import json
p1=json.load(open('/tmp/bn1')); p2=json.load(open('/tmp/bn2'))
ids1=[n['id'] for n in p1.get('notes',[])]
ids2=[n['id'] for n in p2.get('notes',[])]
dups=sorted(set(ids1) & set(ids2))
print("intersección p1∩p2:", len(dups), dups[:20])
PY
fi
