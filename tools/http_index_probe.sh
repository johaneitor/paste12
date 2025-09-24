#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== GET / =="; curl -sS -i "$BASE" | sed -n '1,12p'; echo; echo "body-bytes=$(curl -sS "$BASE" | wc -c | tr -d ' ')"; echo
echo "== GET /index.html =="; curl -sS -i "$BASE/index.html" | sed -n '1,12p'; echo; echo "body-bytes=$(curl -sS "$BASE/index.html" | wc -c | tr -d ' ')"; echo
echo "== GET /?nosw=1 =="; curl -sS -i "$BASE/?nosw=1" | sed -n '1,12p'; echo; echo "body-bytes=$(curl -sS "$BASE/?nosw=1" | wc -c | tr -d ' ')"; echo
