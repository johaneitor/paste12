#!/usr/bin/env bash
set -euo pipefail
FILE="${1:-.env.render}"
read -rsp "Pegá tu RENDER_API_KEY (rv_…): " KEY; echo
read -rp  "Pegá tu RENDER_SERVICE_ID (srv-…): " SID
# Sanea: quita espacios/saltos invisibles
clean_key="$(printf "%s" "$KEY" | tr -d '\r\n' | sed 's/[[:space:]]//g')"
clean_sid="$(printf "%s" "$SID" | tr -d '\r\n' | sed 's/[[:space:]]//g')"
{
  echo "export RENDER_API_KEY=\"$clean_key\""
  echo "export RENDER_SERVICE_ID=\"$clean_sid\""
} > "$FILE"
echo "Guardado en $FILE. Cargá con: source $FILE"
