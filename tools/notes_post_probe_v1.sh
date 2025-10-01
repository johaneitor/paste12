#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
try(){
  local ep="$1"; local mode="$2"; local lbl="${ep} [$mode]"
  if [[ "$mode" == "json" ]]; then
    curl -sS -D - -o /dev/null -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data '{"text":"probe","ttl_hours":12}' "${BASE%/}${ep}"
  else
    curl -sS -D - -o /dev/null -X POST -H 'Accept: application/json' \
      --data-urlencode "text=probe" --data-urlencode "ttl_hours=12" "${BASE%/}${ep}"
  fi
}
for ep in /api/notes /api/note /api/notes/create; do
  for m in json form; do
    echo "== ${ep} [$m] =="; try "$ep" "$m" | sed -n '1,20p'; echo
  done
done
