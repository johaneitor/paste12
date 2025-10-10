#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-${BASE:-http://127.0.0.1:5000}}"
OUTDIR="${2:-${OUTDIR:-./p12-audit}}"
mkdir -p "$OUTDIR"

json() { jq -r "$1" 2>/dev/null || true; }

note_id=""
create() {
  echo "-- create"
  r=$(curl -sS -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"hello from script","ttlHours":4}')
  echo "$r" | tee "$OUTDIR/api-notes-post.json" >/dev/null
  code=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$BASE/api/notes" -H 'Content-Type: application/json' -d '{"text":"hello from script","ttlHours":4}')
  echo "status=$code"
  note_id=$(echo "$r" | jq -r '.id // .item.id // empty')
  if [[ -z "$note_id" ]]; then note_id=$(echo "$r" | jq -r '.item.id'); fi
  echo "id=$note_id"
}

view_dedupe() {
  echo "-- view dedupe"
  fp="fp-$(date +%s)"
  v1=$(curl -sS -X POST "$BASE/api/notes/$note_id/view" -H "X-FP: $fp")
  v2=$(curl -sS -X POST "$BASE/api/notes/$note_id/view" -H "X-FP: $fp")
  echo "$v1" > "$OUTDIR/view-1.json"; echo "$v2" > "$OUTDIR/view-2.json"
}

report_consensus() {
  echo "-- report consensus"
  for i in 1 2 3; do
    fp="rep-$i-$(date +%s)"
    curl -sS -X POST "$BASE/api/notes/$note_id/report" -H "X-FP: $fp" -o "$OUTDIR/report-$i.json"
  done
}

negatives() {
  echo "-- negatives"
  curl -sS "$BASE/api/like?id=99999999" -o "$OUTDIR/neg-like.json"
  curl -sS "$BASE/api/report?id=99999999" -o "$OUTDIR/neg-report.json"
}

create
view_dedupe
report_consensus
negatives

echo "OK"