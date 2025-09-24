#!/usr/bin/env bash
set -euo pipefail

APP="${APP:-https://paste12-rmsk.onrender.com}"

echo "[import]"
curl -sS "$APP/api/diag/import" | jq .

echo "[map]"
curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'

echo "[diag]"
curl -sS "$APP/api/notes/diag" | jq . || true

echo "[repair-interactions]"
curl -sS -X POST "$APP/api/notes/repair-interactions" | jq . || true

echo "[choose note id]"
ID="$(curl -sS "$APP/api/notes?page=1" | jq -r '.[0].id // empty' || true)"
if [ -z "${ID:-}" ]; then
  ID="$(curl -sS -X POST -H 'Content-Type: application/json' -d '{"text":"probe","hours":24}' "$APP/api/notes" | jq -r '.id' || true)"
fi
echo "ID=${ID:-<none>}"

if [ -n "${ID:-}" ]; then
  curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
  curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
  curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'
fi
