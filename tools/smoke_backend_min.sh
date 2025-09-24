#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== health =="; curl -sS "$BASE/api/health" && echo
echo "== terms ==";  curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/terms"
echo "== privacy ==";curl -sS -o /dev/null -w '%{http_code}\n' "$BASE/privacy"
echo "== preflight =="; curl -sS -o /dev/null -w '%{http_code}\n' -X OPTIONS "$BASE/api/notes"
echo "== single-flag (?id=999) =="; curl -sS "$BASE/?id=999&_=$(date +%s)" | grep -q 'data-single="1"' && echo "OK: flag single" || echo "⚠ sin flag"
