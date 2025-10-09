#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-/sdcard/Download}"
MAX_WORDS="${2:-300000}"        # Límite de palabras por archivo resultante
TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR"

# ---------- utilidades ----------
sha256_of() {
  # imprime el SHA256 de $1 o "NA" si no hay herramienta
  local f="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$f" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$f" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    # salida típica: SHA256(filename)= <hash>
    openssl dgst -sha256 -- "$f" | awk '{print $2}'
  else
    echo "NA"
  fi
}

is_text() {
  # heurística rápida por extensión + MIME
  local f="$1"
  case "$f" in
    *.md|*.txt|*.rst|*.py|*.sh|*.bash|*.zsh|*.env|*.toml|*.ini|*.cfg|*.conf|*.yaml|*.yml|*.json|*.sql|*.html|*.css|*.scss|*.ts|*.tsx|*.js|*.mjs|*.cjs|*.jsx|*.vue|*.xml|*.jinja|*.j2|*.tmpl|*.properties|*.gradle|*.gitignore|*.gitattributes|*.editorconfig|Dockerfile|Makefile|Procfile|wsgi|wsgi.py)
      return 0;;
  esac
  if command -v file >/dev/null 2>&1; then
    local mt
    mt="$(file -b --mime-type -- "$f" 2>/dev/null || true)"
    [[ "$mt" =~ ^text/ ]] && return 0
    [[ "$mt" == "application/json" || "$mt" == "application/javascript" || "$mt" == "application/xml" ]] && return 0
    return 1
  fi
  # sin 'file', asumimos texto
  return 0
}

header_global() {
  echo "== paste12 CODE DUMP (by words) =="
  echo "timestamp_utc: $TS"
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    echo "git_head: $(git rev-parse HEAD)"
  fi
  if command -v git >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
    echo "origin: $(git remote get-url origin)"
  fi
  echo "max_words_per_file: $MAX_WORDS"
  echo
}

make_part_path() {
  local idx="$1"
  printf "%s/code-wdump-%s-p%03d.txt" "$OUTDIR" "$TS" "$idx"
}

append_header_and_file() {
  local part="$1" f="$2"
  local size sha
  size="$(wc -c < "$f" | tr -d ' ' || echo 0)"
  sha="$(sha256_of "$f")"
  {
    echo "------------------------------------------------------------"
    echo "FILE: $f"
    echo "SIZE: $size"
    echo "SHA256: $sha"
    echo "------------------------------------------------------------"
    # normalizar EOL -> LF
    sed 's/\r$//' -- "$f" 2>/dev/null || cat -- "$f"
    echo
    echo
  } >> "$part"
}

# ---------- lista de archivos ----------
mapfile -t FILES < <(
  {
    command -v git >/dev/null 2>&1 && git ls-files 2>/dev/null;
    command -v git >/dev/null 2>&1 && git ls-files --others --exclude-standard 2>/dev/null;
  } | sed '/^$/d' | sort -u
)

EXCL_REGEX='(^|/)(\.git/|\.github/|\.venv/|venv/|node_modules/|__pycache__/|\.pytest_cache/|\.mypy_cache/|dist/|build/|\.cache/)'
EXCL_GLOB='*.pyc *.pyo *.so *.dll *.dylib *.o *.a *.bin *.pdf *.png *.jpg *.jpeg *.gif *.webp *.svg *.ico *.lock *.sqlite *.db *.db3 *.tar *.gz *.zip *.7z *.rar *.jar'

# ---------- crear primera parte ----------
part_idx=1
part="$(make_part_path "$part_idx")"
: > "$part"
header_global >> "$part"
curr_words="$(wc -w < "$part" | tr -d ' ' || echo 0)"

TRUNCATED_LIST="$OUTDIR/code-wdump-$TS-truncated.lst"
: > "$TRUNCATED_LIST"

file_count=0
for f in "${FILES[@]:-}"; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ $EXCL_REGEX ]] && continue

  skip=0
  for g in $EXCL_GLOB; do
    [[ "$f" == $g ]] && { skip=1; break; }
  done
  (( skip )) && continue
  is_text "$f" || continue

  # contar palabras aproximadas del bloque (contenido + cabecera)
  hdr_words=20
  fw="$(wc -w < "$f" | tr -d ' ' || echo 0)"
  add_words=$(( fw + hdr_words ))

  # Si no entra en la parte actual, abrir nueva
  if (( curr_words > 0 && curr_words + add_words > MAX_WORDS )); then
    part_idx=$((part_idx+1))
    part="$(make_part_path "$part_idx")"
    : > "$part"
    header_global >> "$part"
    curr_words="$(wc -w < "$part" | tr -d ' ' || echo 0)"
  fi

  # Caso: archivo individual excede límite y la parte está vacía → truncar
  if (( curr_words == 0 && add_words > MAX_WORDS )); then
    allow=$(( MAX_WORDS - hdr_words - 10 ))
    (( allow < 0 )) && allow=0
    echo "TRUNCATE:$f (words=$fw -> $allow)" >> "$TRUNCATED_LIST"
    {
      echo "------------------------------------------------------------"
      echo "FILE: $f"
      echo "SIZE: $(wc -c < "$f" | tr -d ' ')"
      echo "SHA256: $(sha256_of "$f")"
      echo "------------------------------------------------------------"
      sed 's/\r$//' -- "$f" 2>/dev/null \
      | awk -v limit="$allow" '{ c+=NF; print; if (c>=limit) exit }'
      echo
      echo "[[ TRUNCATED HERE to respect MAX_WORDS ]]"
      echo
    } >> "$part"
    curr_words="$(wc -w < "$part" | tr -d ' ' || echo 0)"
    file_count=$((file_count+1))
    continue
  fi

  # Caso normal
  append_header_and_file "$part" "$f"
  curr_words=$(( curr_words + add_words ))
  file_count=$((file_count+1))
done

# Copia conveniente de la PRIMERA parte
FIRST_COPY="$OUTDIR/code-wdump-first-$TS.txt"
cp -f -- "$(make_part_path 1)" "$FIRST_COPY" || true

# ---------- resumen ----------
SUMMARY="$OUTDIR/code-wdump-$TS-summary.txt"
{
  echo "== SUMMARY =="
  echo "timestamp_utc: $TS"
  if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
    echo "git_head: $(git rev-parse HEAD)"
  fi
  if command -v git >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
    echo "origin: $(git remote get-url origin)"
  fi
  echo "files_included: $file_count"
  echo "max_words_per_file: $MAX_WORDS"
  echo
  echo "-- Parts --"
  part_num=1
  while :; do
    p="$(make_part_path "$part_num")"
    [[ -f "$p" ]] || break
    pw="$(wc -w < "$p" | tr -d ' ' || echo 0)"
    ps="$(wc -c < "$p" | tr -d ' ' || echo 0)"
    printf "  p%03d  words=%s  bytes=%s  path=%s\n" "$part_num" "$pw" "$ps" "$p"
    part_num=$((part_num+1))
  done
  echo
  echo "-- Truncated files (if any) --"
  if [[ -s "$TRUNCATED_LIST" ]]; then
    cat "$TRUNCATED_LIST"
  else
    echo "  (none)"
  fi
} > "$SUMMARY"

echo "OK: export listo."
echo " - Primera parte : $FIRST_COPY"
echo " - Resumen       : $SUMMARY"
echo " - Partes:"
ls -1 "$OUTDIR"/code-wdump-"$TS"-p*.txt 2>/dev/null || true
