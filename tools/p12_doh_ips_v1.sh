#!/usr/bin/env bash
set -euo pipefail
HOST="${1:?Uso: $0 HOSTNAME}"
{
  curl -sS -H 'accept: application/dns-json' "https://1.1.1.1/dns-query?name=${HOST}&type=A" || true
  echo
  curl -sS -H 'accept: application/dns-json' "https://1.0.0.1/dns-query?name=${HOST}&type=A" || true
} | tr ',' '\n' \
  | sed -n 's/.*"data":"\([0-9]\{1,3\}\(\.[0-9]\{1,3\}\)\{3\}\)".*/\1/p' \
  | awk '!seen[$0]++'
