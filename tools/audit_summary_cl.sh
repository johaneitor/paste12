#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"

echo "== GET /api/notes?limit=1 (wrapper ON) =="
resp="$(curl -si "$BASE/api/notes?limit=1")"
cl_on="$(printf "%s" "$resp" | awk 'BEGIN{IGNORECASE=1}/^content-length:/{print $2}' | tr -d '\r')"
body_on="$(printf "%s" "$resp" | sed -n '/^\r\?$/,$p' | tail -n +2)"
len_on="$(printf "%s" "$body_on" | wc -c | awk '{print $1}')"
status_on="$(printf "%s" "$resp" | sed -n '1p')"
echo "$status_on"
echo "Content-Length: $cl_on   actual: $len_on"
printf "%s" "$body_on" | head -c 120; echo -e "\n---"

echo
echo "== GET /api/notes?limit=1 (wrapper OFF via header) =="
resp2="$(curl -si "$BASE/api/notes?limit=1" -H 'Disable-Summary-Preview: 1')"
cl_off="$(printf "%s" "$resp2" | awk 'BEGIN{IGNORECASE=1}/^content-length:/{print $2}' | tr -d '\r')"
body_off="$(printf "%s" "$resp2" | sed -n '/^\r\?$/,$p' | tail -n +2)"
len_off="$(printf "%s" "$body_off" | wc -c | awk '{print $1}')"
status_off="$(printf "%s" "$resp2" | sed -n '1p')"
echo "$status_off"
echo "Content-Length: $cl_off   actual: $len_off"
printf "%s" "$body_off" | head -c 120; echo -e "\n---"

echo
if [ -n "${cl_on:-}" ] && [ -n "${len_on:-}" ] && [ "$cl_on" != "$len_on" ]; then
  echo "✗ Mismatch CL (ON): $cl_on vs $len_on  -> bug en wrapper summary"
else
  echo "✓ CL consistente (ON)"
fi
if [ -n "${cl_off:-}" ] && [ -n "${len_off:-}" ] && [ "$cl_off" != "$len_off" ]; then
  echo "✗ Mismatch CL (OFF): $cl_off vs $len_off  (debería ser raro)"
else
  echo "✓ CL consistente (OFF)"
fi
