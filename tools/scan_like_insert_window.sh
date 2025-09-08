#!/usr/bin/env bash
set -euo pipefail
file="wsgiapp/__init__.py"
rg -n --no-heading "INSERT INTO like_log" "$file" | while IFS=: read -r ln _; do
  a=$((ln-20)); b=$((ln+20))
  [ $a -lt 1 ] && a=1
  nl -ba "$file" | sed -n "${a},${b}p"
  echo "---------------------------------------------"
done
