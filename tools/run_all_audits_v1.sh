#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="/sdcard/Download"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
SUMMARY="$OUTDIR/audits-summary-$TS.txt"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta '$1' en el entorno"; exit 2; }; }

# Pre-chequeos
need curl
[ -d "$OUTDIR" ] || { echo "ERROR: $OUTDIR no existe. En Termux corre: termux-setup-storage"; exit 3; }
[ -w "$OUTDIR" ] || { echo "ERROR: $OUTDIR no es escribible. Otorga permisos de almacenamiento."; exit 4; }

echo "== Paste12 Auditorías Unificadas ==" > "$SUMMARY"
echo "BASE: $BASE" >> "$SUMMARY"
echo "TS  : $TS"   >> "$SUMMARY"
echo >> "$SUMMARY"

# Verificar que existan los scripts
FE_SCRIPT="frontend-audit.sh"
BE_SCRIPT="fe-be-audit.sh"
SEO_SCRIPT="seo-audit.sh"

for f in "$FE_SCRIPT" "$BE_SCRIPT" "$SEO_SCRIPT"; do
  if [ ! -x "$f" ]; then
    if [ -f "$f" ]; then chmod +x "$f"; else
      echo "ERROR: falta $f en el directorio actual. Crea primero los scripts de auditoría." | tee -a "$SUMMARY"
      exit 5
    fi
  fi
done

# 0) Salud del backend
echo "-- /api/health --" | tee -a "$SUMMARY"
HEALTH_JSON="$(curl -fsS "$BASE/api/health" || true)"
if [ -n "${HEALTH_JSON:-}" ]; then
  echo "OK  health: $HEALTH_JSON" | tee -a "$SUMMARY"
else
  echo "WARN health: no respondió JSON (continuo con auditorías)" | tee -a "$SUMMARY"
fi
echo >> "$SUMMARY"

# 1) Auditoría Frontend
echo ">> Ejecutando $FE_SCRIPT ..." | tee -a "$SUMMARY"
bash -c "./$FE_SCRIPT"
FE_LATEST="$(ls -1t $OUTDIR/frontend-audit-*.txt 2>/dev/null | head -n 1 || true)"
if [ -n "$FE_LATEST" ]; then
  echo "OK  frontend-audit: $FE_LATEST" | tee -a "$SUMMARY"
else
  echo "ERR frontend-audit: no encontré reporte en $OUTDIR" | tee -a "$SUMMARY"
fi
echo >> "$SUMMARY"

# 2) Auditoría Frontend-Backend
echo ">> Ejecutando $BE_SCRIPT ..." | tee -a "$SUMMARY"
bash -c "./$BE_SCRIPT"
BE_LATEST="$(ls -1t $OUTDIR/fe-be-audit-*.txt 2>/dev/null | head -n 1 || true)"
if [ -n "$BE_LATEST" ]; then
  echo "OK  fe-be-audit: $BE_LATEST" | tee -a "$SUMMARY"
else
  echo "ERR fe-be-audit: no encontré reporte en $OUTDIR" | tee -a "$SUMMARY"
fi
echo >> "$SUMMARY"

# 3) Auditoría SEO
echo ">> Ejecutando $SEO_SCRIPT ..." | tee -a "$SUMMARY"
bash -c "./$SEO_SCRIPT"
SEO_LATEST="$(ls -1t $OUTDIR/seo-audit-*.txt 2>/dev/null | head -n 1 || true)"
if [ -n "$SEO_LATEST" ]; then
  echo "OK  seo-audit: $SEO_LATEST" | tee -a "$SUMMARY"
else
  echo "ERR seo-audit: no encontré reporte en $OUTDIR" | tee -a "$SUMMARY"
fi
echo >> "$SUMMARY"

# Resumen de cabeceras /api/notes (rápido)
echo "-- /api/notes (headers) --" | tee -a "$SUMMARY"
curl -sI "$BASE/api/notes" | sed -n '1,20p' >> "$SUMMARY" || true
echo >> "$SUMMARY"

echo "== FIN =="? | tee -a "$SUMMARY"
echo "Guardado: $SUMMARY"
