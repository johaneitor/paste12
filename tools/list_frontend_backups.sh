#!/usr/bin/env bash
set -euo pipefail
show_for() {
  local f="$1"
  [ -f "$f" ] || return 0
  local d; d="$(dirname "$f")"; local b; b="$(basename "$f")"
  echo "== $f =="
  # Busca variantes comunes de backups creados por nuestros scripts
  find "$d" -maxdepth 1 \
    \( -name "${b}.bak" -o -name "${b}.*.bak" -o -name "${b}.*.p12*.bak" -o -name "${b}.pre_v7*.bak" \) \
    -type f -printf "%T@ %p\n" \
    | sort -nr \
    | head -n 10 \
    | awk '{t=$1; $1=""; sub(/^ /,""); cmd="date -u -d @"t" +%Y-%m-%dT%H:%M:%SZ"; cmd | getline iso; close(cmd); cmd2="wc -c < \""$0"\""; cmd2 | getline bytes; close(cmd2); printf("  - %s  %8s  %s\n", iso, bytes, $0)}'
}
show_for backend/static/index.html
show_for frontend/index.html
