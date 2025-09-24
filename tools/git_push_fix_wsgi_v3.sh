#!/usr/bin/env bash
set -euo pipefail
MSG="${1:-ops: wsgi resolver v3 (fallback seguro)}"
OUT="${2:-/sdcard/Download}"
BASE="${BASE:-https://paste12-rmsk.onrender.com}"

bash -n tools/fix_wsgi_resolver_v3.sh
tools/fix_wsgi_resolver_v3.sh

git add -f tools/fix_wsgi_resolver_v3.sh contract_shim.py wsgi.py || true
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi
echo "== prepush gate ==" && echo "✓ listo"
git push -u origin main

# Pequeño smoke (idempotente) — post-deploy vuelve a correrlo
mkdir -p "$OUT"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
curl -sS "$BASE/api/health" | tee "$OUT/health-$TS.json" >/dev/null || true
echo "[smoke] guardado: $OUT/health-$TS.json"
