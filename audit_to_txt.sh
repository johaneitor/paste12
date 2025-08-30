#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

# carpeta de downloads de Termux (asegurate de correr `termux-setup-storage` antes)
DEST="$HOME/storage/downloads/audit_paste12_$(date +%F_%H%M).txt"

# correr auditor y guardar salida
./audit_paste12.sh | tee "$DEST"

echo "✅ Auditoría guardada en: $DEST"
