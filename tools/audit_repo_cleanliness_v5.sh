#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-/sdcard/Download}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
out="$OUTDIR/repo-audit-${ts}.txt"

# Árbol de trabajo (excluye .git, node_modules, venv, sdcard, dist/ build/)
list_files(){
  find . \
    -path './.git' -prune -o \
    -path './node_modules' -prune -o \
    -path './venv' -prune -o \
    -path './sdcard' -prune -o \
    -path './dist' -prune -o \
    -path './build' -prune -o \
    -type f -print
}

# Reglas simples de higiene (extensibles)
echo "== paste12 repo cleanliness v5 ==" > "$out"
echo "ts: $ts" >> "$out"
echo >> "$out"

# 1) Archivos con finales CRLF
echo "[CRLF files]" >> "$out"
list_files | xargs -r file | grep -nE 'CRLF' || echo "(none)" >> "$out"
echo >> "$out"

# 2) Tabuladores al inicio de línea en .py (indentación sospechosa)
echo "[Tabs in .py]" >> "$out"
list_files | grep -E '\.py$' | xargs -r grep -nP '^\t' || echo "(none)" >> "$out"
echo >> "$out"

# 3) Helpers en una sola línea (riesgo histórico)
echo "[One-liner helpers]" >> "$out"
list_files | grep -E '\.py$' | xargs -r grep -nE '_p12_.*=\s*def|def\s+_p12_.*:.*\\$' || echo "(none)" >> "$out"
echo >> "$out"

# 4) Regex con paréntesis desbalanceados (heurística básica)
echo "[Suspicious regex]" >> "$out"
list_files | grep -E '\.py$' | xargs -r grep -nE 're\.(compile|match|search)\(' | \
  grep -vE '\(\s*\?[iLmsux]' || echo "(none)" >> "$out"
echo >> "$out"

echo "OK: reporte → $out"
