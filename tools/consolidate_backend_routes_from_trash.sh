#!/usr/bin/env bash
set -euo pipefail

# Busca la mejor copia reciente de backend/routes.py dentro de .trash_* y la restaura
# al archivo real backend/routes.py (con backup). No toca nada fuera de eso.

shopt -s globstar nullglob

echo "→ Consolidación de backend/routes.py desde .trash_* (si corresponde)..."

REAL="backend/routes.py"
TS="$(date +%Y%m%d-%H%M%SZ)"

if [[ -f "$REAL" ]]; then
  echo "  • Existe $REAL → backup en ${REAL}.bak.${TS}"
  cp -f "$REAL" "${REAL}.bak.${TS}"
else
  echo "  • No existe $REAL actualmente (se creará si hay candidato)."
fi

# Recolectar candidatos en .trash_* (varias profundidades)
mapfile -t CANDIDATES < <(find . -type f -path "./.trash_*/*" \
  \( -name "routes.py" -o -name "routes.py.bak*" \) -printf "%T@ %p\n" 2>/dev/null | sort -nr | awk '{ $1=""; sub(/^ /,""); print }')

if (( ${#CANDIDATES[@]} == 0 )); then
  echo "  • No hay candidatos en .trash_* → nada para consolidar."
  exit 0
fi

# Elegimos el más reciente
BEST="${CANDIDATES[0]}"
echo "  • Candidato más reciente: $BEST"

# Confirmar que realmente luce como rutas (buscamos al menos /api/notes o Flask decoradores)
if ! grep -Eq "@.*route\(.*/api/notes|/api/notes" "$BEST"; then
  echo "  ! WARNING: el candidato más reciente no parece contener rutas /api/notes."
  echo "    Igual se puede intentar, pero revisá el diff luego."
fi

mkdir -p backend
cp -f "$BEST" "$REAL"

echo "  ✓ Restaurado $REAL desde $BEST"
echo
echo "  Diff rápido contra backup previo (si existía):"
if [[ -f "${REAL}.bak.${TS}" ]]; then
  (diff -u "${REAL}.bak.${TS}" "$REAL" || true) | sed -n '1,120p'
else
  echo "    (no había backup previo del archivo real)"
fi

echo
echo "Listo. Ahora podés abrir backend/routes.py y verificar que tenga las rutas correctas."
