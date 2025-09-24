#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; PAGES="${2:-2}"; LIMIT="${3:-10}"
[ -n "$BASE" ] || { echo "uso: $0 https://host [pages=2] [limit=10]"; exit 2; }
TMP="${TMPDIR:-/tmp}/feed.$$"; mkdir -p "${TMP%/*}"

fetch(){
  local url="$1"
  curl -sS -D "$TMP.h" "$url" -o "$TMP.b" >/dev/null || true
  sed -n '1p' "$TMP.h" | sed 's/^/status: /'
  jq -r '.items[] | @json' < "$TMP.b" 2>/dev/null || true
  grep -i '^Link:' "$TMP.h" | sed -n 's/^[Ll]ink:\s*<\([^>]*\)>;.*$/::next::\1/p'
}

URL="$BASE/api/notes?limit=$LIMIT"
ALL="$TMP.all"
: > "$ALL"
for i in $(seq 1 "$PAGES"); do
  OUT="$(fetch "$URL")"
  echo "$OUT" | sed -n '1p'
  echo "$OUT" | sed -n '2,$p' | grep -v '^::next::' >> "$ALL" || true
  NEXT="$(echo "$OUT" | sed -n 's/^::next::\(.*\)$/\1/p' | head -n1)"
  [ -n "$NEXT" ] || break
  URL="$BASE$NEXT"
done

python - "$ALL" <<'PY'
import sys, json, datetime as dt
from dateutil import parser as p  # suele estar; si no, fallback simple
now = dt.datetime.now(dt.timezone.utc)
raw = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
issues = []
last_ts = None
for it in raw:
    ts = p.parse(it.get("timestamp")) if it.get("timestamp") else None
    ex = p.parse(it.get("expires_at")) if it.get("expires_at") else None
    reps = int(it.get("reports") or 0)
    if ex and ex <= now: issues.append(("EXPIRADO", it["id"], it.get("expires_at")))
    # orden no creciente por timestamp
    if ts and last_ts and ts > last_ts: issues.append(("ORDEN", it["id"], it.get("timestamp")))
    last_ts = ts or last_ts
    # umbral "sugerido" 5 (si tu backend usa os.environ REPORT_THRESHOLD)
    if reps >= 5: issues.append(("REPORTS>=5", it["id"], reps))
print("== Auditoría ==")
if not issues:
    print("✓ sin expirados, orden OK y sin items con reports>=5 en las páginas inspeccionadas")
else:
    for k in issues:
        print("•", k[0], "id=", k[1], "info=", k[2])
PY
