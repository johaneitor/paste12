#!/data/data/com.termux/files/usr/bin/bash
# Limpieza agresiva pero segura (DRY-RUN por defecto)
set -Eeuo pipefail
shopt -s nullglob dotglob

MODE="${1:---dry-run}"   # --dry-run (default) | --apply | --purge
ROOT="$(pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
TRASH=".trash_${STAMP}"

# Requiere estar en la raíz del repo
if [ ! -d ".git" ]; then
  echo "✋ Corré esto en la raíz del repo (donde está .git)"; exit 1
fi

echo "🧹 deep clean ($MODE) — $ROOT"

# Directorios a ignorar por seguridad
PRUNE_DIRS=( "./.git" "./venv" "./$TRASH" )

is_pruned() {
  local p="$1"
  for d in "${PRUNE_DIRS[@]}"; do [[ "$p" == $d* ]] && return 0; done
  return 1
}

# Patrones de archivos/carpeta a limpiar
DIR_PATTERNS=( "__pycache__" ".tmp" ".bak_front" "backups_*" )
FILE_PATTERNS=(
  "*.bak" "*.bak.*" "*.bad.*" "*.tmp" "*.log"
  "*_snapshot_*.txt" "app_snapshot_*.txt" "debug_report_*.txt"
  "app.js.tmp" "index.html.*.bak" "routes.py.*.bak" "styles.css.*.bak"
  "*.db.bak.*"
)

# Candidatos
CAND_DIRS=()
while IFS= read -r -d '' d; do
  is_pruned "${d#.}" && continue
  CAND_DIRS+=( "$d" )
done < <(find . -type d \( -name "${DIR_PATTERNS[0]}" $(printf ' -o -name %q' "${DIR_PATTERNS[@]:1}") \) -print0)

CAND_FILES=()
for pat in "${FILE_PATTERNS[@]}"; do
  while IFS= read -r -d '' f; do
    is_pruned "${f#.}" && continue
    case "$f" in
      ./instance/*.db|./data/*.db|./app.db) continue;;   # no tocar DBs activas
    esac
    CAND_FILES+=( "$f" )
  done < <(find . -type f -name "$pat" -print0)
done

# De-duplicar
dedupe(){ awk '!x[$0]++'; }
mapfile -t CAND_DIRS  < <(printf "%s\n" "${CAND_DIRS[@]}"  | dedupe | sort -u)
mapfile -t CAND_FILES < <(printf "%s\n" "${CAND_FILES[@]}" | dedupe | sort -u)

echo "— Directorios candidatos: ${#CAND_DIRS[@]}"
echo "— Archivos candidatos:    ${#CAND_FILES[@]}"

# Preparar papelera si aplica
[ "$MODE" = "--apply" ] && mkdir -p "$TRASH"

move_or_rm() {
  local src="$1"
  # si está trackeado por git, no lo tocamos
  if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    echo "↷ SKIP (trackeado)  $src"; return 0
  fi
  case "$MODE" in
    --dry-run) echo "• would remove: $src" ;;
    --apply)
      mkdir -p "$TRASH/$(dirname "$src")"
      echo "→ move $src → $TRASH/$src"
      mv -f "$src" "$TRASH/$src"
      ;;
    --purge)
      echo "✖ rm   $src"
      rm -rf -- "$src"
      ;;
    *) echo "modo inválido: $MODE"; exit 2;;
  esac
}

# 1) Archivos
for f in "${CAND_FILES[@]}"; do move_or_rm "$f"; done

# 2) Directorios (del más profundo al más superficial)
for (( i=${#CAND_DIRS[@]}-1; i>=0; i-- )); do
  d="${CAND_DIRS[$i]}"
  if [ "$MODE" = "--dry-run" ]; then
    echo "• would remove dir: $d"
  else
    # borrar sólo si vacía o temporal conocida
    if [ -z "$(ls -A "$d" 2>/dev/null || true)" ] || [[ "$d" =~ (__pycache__|\.tmp|\.bak_front|backups_) ]]; then
      move_or_rm "$d"
    else
      echo "↷ SKIP (no vacía/mixta): $d"
    fi
  fi
done

echo
if [ "$MODE" = "--apply" ]; then
  echo "✅ Movidos a papelera: $TRASH (revisá y luego podés purgarla)"
elif [ "$MODE" = "--purge" ]; then
  echo "☠️  Purga definitiva hecha."
else
  echo "🔎 DRY-RUN. Para aplicar:  ./deep_clean_paste12.sh --apply"
fi

echo
echo "🔁 Post-check (git):"
git status --short || true
