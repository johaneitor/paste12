#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: push}"
BR="$(git branch --show-current 2>/dev/null || echo main)"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
OUT_BASE="/sdcard/Download"

echo "== sanity =="
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es repo git"; exit 2; }

echo "== status =="
git status -sb || true

# Si hay cambios, commit rápido
if [[ -n "$(git status --porcelain)" ]]; then
  echo "== commit =="
  git add -A
  git commit -m "$MSG" || true
fi

echo "== DNS check github.com =="
python - <<'PY' || exit 3
import socket; socket.getaddrinfo("github.com", 443); print("OK")
PY

echo "== push origin ${BR} =="
git push -u origin "$BR"
echo "OK: push completado"
exit 0

# Si fallara algo arriba, creamos artefactos offline
# (este bloque sólo corre si el push no llegó a ejecutarse)
trap 'RC=$?; if [ $RC -ne 0 ]; then
  echo "== fallback offline =="
  mkdir -p "$OUT_BASE"
  BUNDLE="$OUT_BASE/paste12-${BR}-${TS}.bundle"
  echo "Creando bundle: $BUNDLE"
  # incluye todas las ramas y tags por seguridad
  git bundle create "$BUNDLE" --all

  # patches desde el remoto (si existe) o merge-base
  PATCH_DIR="$OUT_BASE/patches-${TS}"
  mkdir -p "$PATCH_DIR"
  MB="$(git merge-base ${BR} @{u} 2>/dev/null || echo "")"
  if [[ -n "$MB" ]]; then
    git format-patch "$MB"..HEAD -o "$PATCH_DIR" || true
  else
    # si no hay upstream trackeado, saca todo el historial actual (limitado)
    git format-patch --root -o "$PATCH_DIR" || true
  fi

  echo "== artefactos offline list =="
  echo "  bundle : $BUNDLE"
  echo "  patches: $PATCH_DIR"
  echo
  echo "Cómo usar el bundle en otra máquina:"
  echo "  git clone paste12-${BR}-${TS}.bundle -b ${BR} paste12-offline"
  echo "o para traer commits a un repo existente:"
  echo "  git fetch paste12-${BR}-${TS}.bundle ${BR}:${BR}"
  exit $RC
fi' EXIT
