#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT="${HOME}/storage/downloads/audit-${TS}.txt"
tmp="$(mktemp)"
{
  echo "===== INFO ====="
  echo "Base: $BASE"
  echo "UTC:  $(date -u)"
  echo
  echo "===== SALUD & DEPLOY ====="
  curl -sI "$BASE/api/health" | sed -n '1,999p'
  echo
  curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | jq -r '.commit' || echo "<deploy-stamp ausente>"
  echo
  echo "===== HEADERS / ====="
  curl -sI "$BASE/" | sed -n '1,999p'
  echo
  echo "===== UI: BRAND & TAGLINE & PREVIEW ====="
  HTML="$(curl -fsS "$BASE/")"
  printf "h1.brand: %s   " "$(echo "$HTML" | grep -io '<h1[^>]*class=\"[^\"]*brand[^\"]*\"[^>]*>' | wc -l)"
  printf "tagline-rot: %s   " "$(echo "$HTML" | grep -io 'id=\"tagline-rot\"' | wc -l)"
  printf "tagline (fijos): %s   " "$(echo "$HTML" | grep -io 'id=\"tagline\"' | wc -l)"
  printf "'Ver más': %s\n" "$(echo "$HTML" | grep -io 'Ver más' | wc -l)"
  echo
  echo "===== TTL (CAP anunciado y efectivo) ====="
  curl -sI "$BASE/" | awk 'BEGIN{IGNORECASE=1}/^X-Max-TTL-Hours:/{print}'
  J=$(jq -n --arg t "ttl probe $(date -u +%H:%M:%S) — xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" '{text:$t}')
  NID=$(echo "$J" | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id')
  if [ -n "$NID" ]; then
    FULL=$(curl -fsS "$BASE/api/notes/$NID")
    ts=$(echo "$FULL" | jq -r '.item.timestamp')
    ex=$(echo "$FULL" | jq -r '.item.expires_at')
    python - "$ts" "$ex" <<'PY'
import sys,datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
t1,t2=p(sys.argv[1]),p(sys.argv[2])
print("timestamp:", t1)
print("expires  :", t2)
print("TTL(h)   :", f"{(t2-t1).total_seconds()/3600:.2f}")
PY
  else
    echo "(POST /api/notes falló para medir TTL)"
  fi
  echo
  echo "===== LIKES (dedupe y concurrencia corta) ====="
  N2=$(jq -n --arg t "likes probe $(date -u +%H:%M:%S) — xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" '{text:$t}' \
        | curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" | jq -r '.item.id')
  if [ -n "$N2" ]; then
    a=$(curl -fsS -X POST "$BASE/api/notes/$N2/like" | jq -r '.likes,.deduped' | paste -sd' ')
    b=$(curl -fsS -X POST "$BASE/api/notes/$N2/like" | jq -r '.likes,.deduped' | paste -sd' ')
    echo "same-FP: $a -> $b"
    curl -fsS -X POST "$BASE/api/notes/$N2/like" -H 'X-FP: A' >/dev/null
    curl -fsS -X POST "$BASE/api/notes/$N2/like" -H 'X-FP: B' >/dev/null
    curl -fsS -X POST "$BASE/api/notes/$N2/like" -H 'X-FP: C' >/dev/null
    fin=$(curl -fsS "$BASE/api/notes/$N2" | jq -r '.item.likes')
    echo "likes finales (esp 4): $fin"
    before="$fin"
    for i in $(seq 1 10); do (curl -fsS -o /dev/null -X POST "$BASE/api/notes/$N2/like" -H 'X-FP: Z') & done
    wait
    after=$(curl -fsS "$BASE/api/notes/$N2" | jq -r '.item.likes')
    echo "race Z: antes=$before despues=$after delta=$((after-before))"
  else
    echo "(no pude crear nota para likes)"
  fi
  echo
  echo "===== PAGINACIÓN (page1, Link next, X-Next-Cursor) ====="
  R=$(curl -fsS -i "$BASE/api/notes?limit=5")
  echo "$R" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}'
  echo "$R" | awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{print}'
  echo "$R" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}' | jq -r '.items[].id' | sed 's/^/  id: /'
  echo
  echo "===== FIN ====="
} > "$tmp"

mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
cp "$tmp" "$OUT"
rm -f "$tmp"
echo "Guardado en: $OUT"
