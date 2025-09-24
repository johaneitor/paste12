#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
LIMIT="${2:-5}"        # items por página (pequeño para no cargar)
MAXPAGES="${3:-15}"    # páginas a recorrer en el smoke

pass=0; fail=0
ok(){ echo "✓ $*"; pass=$((pass+1)); }
bad(){ echo "✗ $*"; fail=$((fail+1)); }
hr(){ printf -- "---------------------------------------------\n"; }
jget(){ jq -r "$1" 2>/dev/null || echo ""; }

echo "== PAGE 1 =="
resp="$(curl -fsS -i "$BASE/api/notes?limit=$LIMIT")"
code="$(printf "%s" "$resp" | head -n1 | awk '{print $2}' | tr -d '\r')"
[ "$code" = "200" ] || { bad "GET page1 → $code"; exit 1; }

body="$(printf "%s" "$resp" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}')"
link_next="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"
xnext="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^x-next-cursor:/{sub(/^x-next-cursor:\s*/,"");print}')"

ids="$(printf "%s" "$body" | jq -r '.items[].id' 2>/dev/null || true)"
cnt="$(printf "%s" "$ids" | grep -c . || true)"
[ "$cnt" -gt 0 ] && ok "items page1 = $cnt" || bad "page1 vacía"

tmp_ids="$(mktemp)"; printf "%s\n" $ids > "$tmp_ids"
min_ts="$(printf "%s" "$body" | jq -r '.items[-1].timestamp' 2>/dev/null || true)"

[ -n "$link_next" ] && ok "Link: next presente" || echo "(aviso) Link next ausente"
[ -n "$xnext" ] && ok "X-Next-Cursor presente"  || echo "(aviso) X-Next-Cursor ausente"
hr

i=1
next_url="$link_next"
while [ -n "${next_url:-}" ] && [ $i -lt $MAXPAGES ]; do
  i=$((i+1))
  [[ "$next_url" =~ ^/ ]] && next_url="$BASE$next_url"

  echo "== PAGE $i =="
  resp="$(curl -fsS -i "$next_url")" || break
  code="$(printf "%s" "$resp" | head -n1 | awk '{print $2}' | tr -d '\r')"
  [ "$code" = "200" ] || { bad "GET page $i → $code"; break; }

  body="$(printf "%s" "$resp" | awk 'BEGIN{p=0}/^\r?$/{p=1;next} p{print}')"
  link_next="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^link:/{print}' | sed -n 's/.*<\([^>]*\)>\;\s*rel="next".*/\1/p')"

  ids="$(printf "%s" "$body" | jq -r '.items[].id' 2>/dev/null || true)"
  cnt="$(printf "%s" "$ids" | grep -c . || true)"
  [ "$cnt" -gt 0 ] && ok "items page $i = $cnt" || { echo "(fin) sin items"; break; }

  dups=$({ cat "$tmp_ids"; printf "%s\n" $ids; } | sort -n | uniq -d | wc -l | awk '{print $1}')
  [ "$dups" -eq 0 ] && ok "sin duplicados acumulados" || bad "duplicados detectados ($dups)"

  cur_min_ts="$(printf "%s" "$body" | jq -r '.items[-1].timestamp' 2>/dev/null || true)"
  python - "$min_ts" "$cur_min_ts" <<'PY' >/dev/null 2>&1 || exit 99
import sys, datetime as dt
def p(s):
  try: return dt.datetime.fromisoformat(s.replace("Z","+00:00"))
  except: return dt.datetime.fromisoformat(s.split('.')[0])
prev,cur = p(sys.argv[1]), p(sys.argv[2])
assert cur <= prev
PY
  if [ $? -eq 0 ]; then ok "orden cronológico estable (↓)"; else bad "orden no estable"; fi

  printf "%s\n" $ids >> "$tmp_ids"
  min_ts="$cur_min_ts"
  next_url="$link_next"
  [ -n "$next_url" ] || echo "(fin) no hay Link next"
  hr
done

total="$(cat "$tmp_ids" | wc -l | awk '{print $1}')"
echo "Páginas recorridas: $i"
echo "Items únicos:      $total"
rm -f "$tmp_ids"
