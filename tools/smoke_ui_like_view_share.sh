#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
say(){ echo -e "$*"; }

TMP="${TMPDIR:-/tmp}/ui.$$"; mkdir -p "$TMP"
HDR="$TMP/h"; BODY="$TMP/b"

# 1) toma una nota existente o crea una
ID="$(curl -fsS "$BASE/api/notes?limit=1" | sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p' | head -1 || true)"
if [ -z "$ID" ]; then
  say "== creando nota =="
  ID="$(curl -fsS -X POST "$BASE/api/notes" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data 'text=smoke like/view/share & ttl_hours=12' \
        | sed -n 's/.*"id":\s*\([0-9]\+\).*/\1/p')"
fi
[ -n "$ID" ] || { echo "✗ no hay id"; exit 1; }
say "ID=$ID"

# 2) like
LIKE_BEFORE="$(curl -fsS "$BASE/api/notes/$ID" | sed -n 's/.*"likes":\s*\([0-9]\+\).*/\1/p')"
curl -fsS -X POST "$BASE/api/notes/$ID/like" >/dev/null || true
LIKE_AFTER="$(curl -fsS "$BASE/api/notes/$ID" | sed -n 's/.*"likes":\s*\([0-9]\+\).*/\1/p')"
say "likes: $LIKE_BEFORE -> $LIKE_AFTER"

# 3) vista
VIEW_BEFORE="$(curl -fsS "$BASE/api/notes/$ID" | sed -n 's/.*"views":\s*\([0-9]\+\).*/\1/p')"
curl -fsS -X POST "$BASE/api/notes/$ID/view" >/dev/null || true
VIEW_AFTER="$(curl -fsS "$BASE/api/notes/$ID" | sed -n 's/.*"views":\s*\([0-9]\+\).*/\1/p')"
say "views: $VIEW_BEFORE -> $VIEW_AFTER"

# 4) página de nota única (?id=)
curl -sS "$BASE/?id=$ID&nosw=1" -o "$BODY"
grep -q "#$ID" "$BODY" && say "✓ modo nota única visible" || say "⚠ no detecté render de nota única"

echo "Listo."
