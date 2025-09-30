#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://<servicio>.onrender.com}"
JSON="${HOME}/.cache/p12/services.json"
CSV="${HOME}/.cache/p12/services.csv"

tools/render_fetch_services_v3.sh >/dev/null
python tools/render_services_to_csv_v2.py "$JSON" > "$CSV"

# 1) match exacto por URL
srv="$(awk -F, -v base="$BASE" 'NR>1 && $4==base {print $1; exit}' "$CSV")"
if [ -n "$srv" ]; then
  echo "export RENDER_SERVICE_ID=\"$srv\""
  echo "echo OK: service $srv (por url=$BASE)"
  exit 0
fi

# 2) fallback: repo termina en johaneitor/paste12 y branch=main y type=web_service
srv="$(awk -F, 'NR>1 && $5 ~ /johaneitor\/paste12$/ && $6=="main" && $3=="web_service" {print $1; exit}' "$CSV")"
if [ -n "$srv" ]; then
  name="$(awk -F, -v id="$srv" 'NR>1 && $1==id {print $2; exit}' "$CSV")"
  url="$(awk -F, -v id="$srv" 'NR>1 && $1==id {print $4; exit}' "$CSV")"
  echo "export RENDER_SERVICE_ID=\"$srv\""
  echo "echo WARN: url no coincide/None; usando $srv name=$name url=$url repo=paste12 branch=main"
  exit 0
fi

echo "echo ERROR: no encontré service por url ni por repo/main"
echo "exit 2"
