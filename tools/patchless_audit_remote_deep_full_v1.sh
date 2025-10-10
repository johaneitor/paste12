#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
OUTDIR="${2:-${OUTDIR:-./p12-audit}}"
mkdir -p "$OUTDIR"

h() { curl -sS -D - -o /dev/null "$1"; }

# Index and headers
curl -sS "$BASE/" -o "$OUTDIR/index-remote.html"
h "$BASE/" > "$OUTDIR/index-remote-headers.txt"

# FE flags
awk '/p12-commit|p12-safe-shim|data-single/ {print}' "$OUTDIR/index-remote.html" > "$OUTDIR/fe-flags.txt" || true

# Deploy stamp
curl -sS "$BASE/api/deploy-stamp" -o "$OUTDIR/deploy-stamp.json"

# Health
curl -sS "$BASE/api/health" -o "$OUTDIR/health.json"
(curl -sS "$BASE/api/health/db" || true) > "$OUTDIR/health-db.json"

# Notes list
curl -sS "$BASE/api/notes?limit=10" -o "$OUTDIR/api-notes-get.json"

# POST note
curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"hello remote","ttlHours":6}' -o "$OUTDIR/api-notes-post.json" -D "$OUTDIR/api-notes-post.h"

# View dedupe
nid=$(python3 - <<'PY'
import json,sys
try:
  j=json.load(open(sys.argv[1]))
  print(j.get('item',{}).get('id') or j.get('id') or '')
except Exception:
  print('')
PY
"$OUTDIR/api-notes-post.json")
if [[ -n "$nid" ]]; then
  curl -sS -X POST "$BASE/api/notes/$nid/view" -H 'X-FP: abc123' -o "$OUTDIR/view-1.json"
  curl -sS -X POST "$BASE/api/notes/$nid/view" -H 'X-FP: abc123' -o "$OUTDIR/view-2.json"
  # Report consensus
  for i in 1 2 3; do curl -sS -X POST "$BASE/api/notes/$nid/report" -H "X-FP: r$i" -o "$OUTDIR/report-$i.json"; done
fi

# Rate limit probe (best-effort)
for i in $(seq 1 25); do curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"rl"}' -o /dev/null || true; done

# Negatives
(curl -sS "$BASE/api/like?id=99999999" || true) > "$OUTDIR/negatives-like.txt"
(curl -sS "$BASE/api/report?id=99999999" || true) > "$OUTDIR/negatives-report.txt"

echo "DONE"