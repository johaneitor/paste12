#!/usr/bin/env bash
set -euo pipefail
export TMPDIR="${TMPDIR:-$HOME/tmp}"; mkdir -p "$TMPDIR"

BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== BE: preflight =="; curl -sS -i -X OPTIONS "$BASE/api/notes" | sed -n '1,15p'

TMPIDX="$(mktemp -p "$TMPDIR" idx.XXXXXX)"
curl -fsS "$BASE/?nosw=1&_=$(date +%s)" -o "$TMPIDX" || true
echo "== FE: index (sin SW) =="
echo "bytes=$(wc -c < "$TMPIDX" | tr -d ' ')"
echo "marker_safe_shim: $(grep -qiF 'name=\"p12-safe-shim\"' "$TMPIDX" && echo yes || echo no)"
echo "marker_single_meta: $(grep -qiF 'name=\"p12-single\"' "$TMPIDX" && echo yes || echo no)"
echo
echo "== BE: list =="
curl -sS -i "$BASE/api/notes?limit=3" | sed -n '1,20p'
