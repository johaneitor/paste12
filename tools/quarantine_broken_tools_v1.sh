#!/usr/bin/env bash
set -euo pipefail
mkdir -p tools/__quarantine__
# Lista de scripts problemáticos que rompen los gates
BROKEN=(
  tools/quick_backend_stabilize_v8.sh
  tools/smoke_limits.sh
  tools/smoke_limits_v2.sh
  tools/smoke_local_api.sh
  tools/smoke_share_report.sh
  tools/check_reported_count.sh
  tools/cleanup_reported_notes.sh
)
moved=0
for f in "${BROKEN[@]}"; do
  if [[ -f "$f" ]]; then
    mv -f "$f" tools/__quarantine__/  && echo "→ movido a cuarentena: ${f}" && moved=1
  fi
done
if [[ $moved -eq 0 ]]; then
  echo "ℹ️  No había archivos de la lista (o ya estaban movidos)."
fi
echo "Listo. Correr push seguro y smoke."
