#!/usr/bin/env bash
# Simple concurrent POSTs to /api/notes/:id/view against a staging URL
# Usage:
#   ./tools/staging_load_views.sh https://staging.example.com 123 --concurrency 50 --requests 500
# Notes:
# - Use ONLY against staging. This script sends write traffic.
# - Requires: bash, curl, xargs
set -Eeuo pipefail

if [[ ${1:-} == "" || ${2:-} == "" ]]; then
  echo "Usage: $0 <BASE_URL> <NOTE_ID> [--concurrency N] [--requests M]" >&2
  exit 1
fi
BASE_URL="$1"; shift
NOTE_ID="$1"; shift
CONCURRENCY=20
REQUESTS=200
FP_HEADER=${FP_HEADER:-"X-Fingerprint: test-load"}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --concurrency) CONCURRENCY="$2"; shift 2;;
    --requests) REQUESTS="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

url="${BASE_URL%/}/api/notes/${NOTE_ID}/view"
echo "Target: $url"
echo "Concurrency: $CONCURRENCY  Requests: $REQUESTS"

echo "$(date -Is) starting..."
seq 1 "$REQUESTS" | xargs -I{} -P "$CONCURRENCY" bash -c \
  'sleep $(awk -v seed=$RANDOM "BEGIN{srand(seed); printf \"%.3f\", rand()/10}"); \
    curl -sS -X POST -H "Content-Type: application/json" -H "'$FP_HEADER'" "$0" || true' "$url" \
  | awk 'BEGIN{s=0;} /\{/{s++} END{print "responses:", s}'

echo "Done $(date -Is)"
