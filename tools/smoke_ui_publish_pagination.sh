#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }

echo "== health =="; curl -fsS "$BASE/api/health"; echo

echo "== list =="; curl -fsS "$BASE/api/notes?limit=3" -i | sed -n '1,20p'; echo
NEXT="$(curl -fsSI "$BASE/api/notes?limit=3" | awk -F'[<>]' '/[Ll]ink: /{print $2}')"
[ -n "$NEXT" ] && echo "next: $NEXT" || echo "sin next (poca data?)"

echo "== create JSON (ttl_hours) ==";
printf '{"text":"shim smoke %s abcdefghij","ttl_hours":12}\n' "$(date -u +%H:%M:%SZ)" \
| curl -fsS -H 'Content-Type: application/json' --data-binary @- "$BASE/api/notes" || true; echo

echo "== create FORM fallback ==";
printf 'text=%s&ttl_hours=12\n' "shim smoke $(date -u +%H:%M:%SZ) abcdefghij" \
| curl -fsS -H 'Content-Type: application/x-www-form-urlencoded' --data-binary @- "$BASE/api/notes" || true; echo
