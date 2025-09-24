#!/usr/bin/env bash
set -euo pipefail

# ---------- Requisitos / comprobaciones ----------
command -v jq >/dev/null 2>&1 || { echo "[!] Falta 'jq'. Instálalo con: pkg install jq"; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "[!] Falta 'zip'. Instálalo con: pkg install zip"; exit 1; }
[ -d /sdcard ] || { echo "[!] No hay acceso a /sdcard. Ejecuta una vez: termux-setup-storage"; exit 1; }

APP="${APP:-}"
if [ -z "$APP" ]; then
  echo "[!] Debes exportar la URL de tu app, ej.:"
  echo "    export APP=\"https://paste12-rmsk.onrender.com\""
  exit 1
fi

# ---------- Directorios de trabajo / salida ----------
WORK="$(mktemp -d)"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="/sdcard/Download/remote_audit_${STAMP}"
OUT_ZIP="${OUT_DIR}.zip"
mkdir -p "$OUT_DIR"

echo "[i] Descargando auditoría desde: $APP"

# Helper: descarga URL a archivo (sin cortar en 404/500) y guarda headers
fetch() {
  local url="$1" out="$2"
  curl -sS -D "${out}.headers" "$url" -o "$out" || true
}

# ---------- 1) Descargas remotas ----------
echo "$APP" > "$WORK/app_url.txt"
fetch "$APP/api/diag/import"      "$WORK/diag_import.json"
fetch "$APP/api/health"           "$WORK/health.json"
fetch "$APP/api/version"          "$WORK/version.raw"
fetch "$APP/api/debug-urlmap"     "$WORK/debug_urlmap.json"
fetch "$APP/api/notes/diag"       "$WORK/notes_diag.raw"
fetch "$APP/api/notes?page=1"     "$WORK/notes_page1.raw"

# ---------- 2) Crea un _SUMMARY.txt rápido ----------
{
  echo "APP: $APP"
  echo "Fecha: $(date)"
  echo "--- diag/import (resumen) ---"
  jq -r '.import_path as $p | .import_error as $e | "import_path=\($p) | import_error=\($e) | ok=\(.ok)"' "$WORK/diag_import.json" 2>/dev/null \
    || { echo "(sin JSON válido)"; sed -n '1,60p' "$WORK/diag_import.json"; }
} > "$WORK/_SUMMARY.txt"

# ---------- 3) Genera AUDIT_REPORT.txt (consolidado) ----------
{
  echo "=== Auditoría remota paste12 ==="
  echo "Fecha: $(date)"
  echo
  echo "[*] App:"
  cat "$WORK/app_url.txt"
  echo
  echo "[*] diag/import:"
  jq . "$WORK/diag_import.json" 2>/dev/null || { echo "--- raw ---"; sed -n '1,200p' "$WORK/diag_import.json"; }
  echo
  echo "[*] health:"
  jq . "$WORK/health.json" 2>/dev/null || { echo "--- raw ---"; sed -n '1,200p' "$WORK/health.json"; }
  echo
  echo "[*] version:"
  sed -n '1,120p' "$WORK/version.raw" 2>/dev/null || true
  echo
  echo "[*] debug-urlmap:"
  jq . "$WORK/debug_urlmap.json" 2>/dev/null || { echo "--- raw ---"; sed -n '1,200p' "$WORK/debug_urlmap.json"; }
  echo
  echo "[*] notes/diag:"
  sed -n '1,200p' "$WORK/notes_diag.raw" 2>/dev/null || true
  echo
  echo "[*] notes?page=1:"
  sed -n '1,200p' "$WORK/notes_page1.raw" 2>/dev/null || true
  echo
  echo "[*] Summary:"
  sed -n '1,120p' "$WORK/_SUMMARY.txt"
} > "$WORK/AUDIT_REPORT.txt"

# ---------- 4) Copia todo al OUT_DIR ----------
cp -v "$WORK/"* "$OUT_DIR/" || true

# ---------- 5) ZIP en Downloads ----------
( cd /sdcard/Download && zip -r "$(basename "$OUT_ZIP")" "$(basename "$OUT_DIR")" >/dev/null )

echo "[ok] Auditoría consolidada:"
echo " - Carpeta: $OUT_DIR"
echo " - ZIP:     $OUT_ZIP"
