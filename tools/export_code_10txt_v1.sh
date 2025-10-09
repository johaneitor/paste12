#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR"

# --- 1) Recolectar archivos del repo (tracked + untracked) ---
mapfile -t FILES < <(
  { git ls-files; git ls-files --others --exclude-standard; } \
  | sort -u
)

# Patrones a excluir (binarios, cachés, dependencias)
EXCL_REGEX='(^|/)(\.git/|\.github/|\.venv/|venv/|node_modules/|__pycache__/|\.pytest_cache/|\.mypy_cache/|dist/|build/|\.cache/)'
EXCL_GLOB='*.pyc *.pyo *.so *.dll *.dylib *.o *.a *.bin *.pdf *.png *.jpg *.jpeg *.gif *.webp *.svg *.ico *.lock *.sqlite *.db *.db3 *.tar *.gz *.zip *.7z *.rar *.jar'

# Función: ¿es texto?
is_text () {
  local f="$1"
  # Filtro por extensión primero (rápido)
  case "$f" in
    *.md|*.txt|*.rst|*.py|*.sh|*.bash|*.zsh|*.env|*.toml|*.ini|*.cfg|*.conf|*.yaml|*.yml|*.json|*.sql|*.html|*.css|*.scss|*.ts|*.tsx|*.js|*.mjs|*.cjs|*.jsx|*.vue|*.xml|*.jinja|*.j2|*.tmpl|*.properties|*.gradle|*.gitignore|*.gitattributes|*.editorconfig|Dockerfile|Makefile|Procfile|wsgi|wsgi.py)
      return 0;;
  esac
  # Consulta al sistema (si está disponible)
  if command -v file >/dev/null 2>&1; then
    local mt
    mt="$(file -b --mime-type -- "$f" 2>/dev/null || echo '')"
    [[ "$mt" =~ ^text/ ]] && return 0
    [[ "$mt" == "application/json" || "$mt" == "application/javascript" || "$mt" == "application/xml" ]] && return 0
    return 1
  fi
  # Fallback: asumir texto
  return 0
}

# --- 2) Construir un "libro" monolítico con separadores y metadatos ---
BIG="$OUTDIR/code-all-$TS.txt"
: > "$BIG"

# Encabezado general
echo "== paste12 CODE DUMP ==" >> "$BIG"
echo "timestamp_utc: $TS" >> "$BIG"
git rev-parse HEAD >/dev/null 2>&1 && echo "git_head: $(git rev-parse HEAD)" >> "$BIG" || true
git remote get-url origin >/dev/null 2>&1 && echo "origin: $(git remote get-url origin)" >> "$BIG" || true
echo >> "$BIG"

count=0
for f in "${FILES[@]}"; do
  # excluir por regex de rutas
  if [[ "$f" =~ $EXCL_REGEX ]]; then
    continue
  fi
  # excluir por globs
  skip=0
  for g in $EXCL_GLOB; do
    [[ "$f" == $g ]] && { skip=1; break; }
  done
  (( skip )) && continue
  # requerir que exista y sea texto
  [[ -f "$f" ]] || continue
  if ! is_text "$f"; then
    continue
  fi
  size="$(wc -c < "$f" | tr -d ' ')"
  sha="$( (command -v sha256sum >/dev/null && sha256sum -- "$f" | awk '{print $1}') || (command -v shasum >/dev/null && shasum -a 256 -- "$f" | awk '{print $1}') || echo 'NA' )"
  echo "------------------------------------------------------------" >> "$BIG"
  echo "FILE: $f" >> "$BIG"
  echo "SIZE: $size" >> "$BIG"
  echo "SHA256: $sha" >> "$BIG"
  echo "------------------------------------------------------------" >> "$BIG"
  # normalizar EOL a LF
  sed 's/\r$//' -- "$f" >> "$BIG" || cat -- "$f" >> "$BIG"
  echo -e "\n" >> "$BIG"
  ((count++))
done

echo "OK: consolidado $count archivo(s) en $BIG"

# --- 3) Partir en 10 textos grandes ---
# split por líneas para mantener legible
split -d -n l/10 -a 2 -- "$BIG" "$OUTDIR/code-part-$TS-"
# Renombrar a 01..10
i=0
for p in "$OUTDIR"/code-part-"$TS"-??; do
  n=$(printf "%02d" $((i+1)))
  mv -f -- "$p" "$OUTDIR/code-$n-of-10-$TS.txt"
  i=$((i+1))
done

echo "== Archivos generados =="
ls -lh "$OUTDIR"/code-*-of-10-"$TS".txt
echo "Listo. Sugerencia: comparte los 10 .txt junto con $BIG si querés también el monolítico."
