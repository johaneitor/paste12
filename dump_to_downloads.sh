#!/usr/bin/env bash
set -Eeuo pipefail

# -- Elegir carpeta de destino visible en Android --
OUTDIR=""
for d in "$HOME/storage/downloads" "/sdcard/Download" "$HOME/Downloads" "$HOME/Download"; do
  [ -d "$d" ] && OUTDIR="$d" && break
done
if [ -z "${OUTDIR:-}" ]; then
  mkdir -p "$HOME/Downloads"
  OUTDIR="$HOME/Downloads"
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTFILE="$OUTDIR/paste12_snapshot_${STAMP}.txt"

echo "### SNAPSHOT @ \$(date -Iseconds)" > "$OUTFILE"

{
  echo
  echo "===== GIT ====="
  ( git rev-parse --abbrev-ref HEAD 2>/dev/null || true )
  ( git remote -v 2>/dev/null || true )
  ( git status -s 2>/dev/null || true )
  ( git log --oneline -n 15 2>/dev/null || true )

  echo
  echo "===== TREE (hasta 3 niveles) ====="
  if command -v tree >/dev/null 2>&1; then
    tree -a -L 3 -I ".git|venv|.venv|instance|backups_*"
  else
    find . \
      -path './.git' -prune -o \
      -path './venv' -prune -o \
      -path './.venv' -prune -o \
      -path './instance' -prune -o \
      -name 'backups_*' -prune -o \
      -maxdepth 3 -print | sort
  fi

  echo
  echo "===== LISTA DE ARCHIVOS (código) ====="
} >> "$OUTFILE"

find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.css' -o -name 'Dockerfile' -o -name 'Procfile' -o -name '*.yml' -o -name '*.yaml' -o -name 'render.yaml' -o -name 'render.yml' -o -name 'requirements.txt' \) \
  -not -path './.git/*' -not -path './venv/*' -not -path './.venv/*' -not -path './instance/*' -not -path './backups_*/*' \
  | sort | tee -a "$OUTFILE" >/dev/null

echo -e "\n===== CONTENIDO DE ARCHIVOS =====" >> "$OUTFILE"
while IFS= read -r f; do
  echo -e "\n----- BEGIN FILE: \$f -----" >> "$OUTFILE"
  sed -n '1,200000p' "\$f" >> "$OUTFILE" || echo "[[ no se pudo leer \$f ]]" >> "$OUTFILE"
  echo -e "----- END FILE: \$f -----" >> "$OUTFILE"
done < <(find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.css' -o -name 'Dockerfile' -o -name 'Procfile' -o -name '*.yml' -o -name '*.yaml' -o -name 'render.yaml' -o -name 'render.yml' -o -name 'requirements.txt' \) \
          -not -path './.git/*' -not -path './venv/*' -not -path './.venv/*' -not -path './instance/*' -not -path './backups_*/*' \
          | sort)

# Resumen de rutas Flask (opcional)
{
  echo
  echo "===== FLASK URL MAP ====="
  python - <<'PY'
import os, sys, traceback
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app
    app = create_app()
    print("static_folder:", getattr(app, "static_folder", None))
    rules = sorted(app.url_map.iter_rules(), key=lambda r: (r.rule, ",".join(sorted(r.methods))))
    for r in rules:
        methods = ",".join(sorted(m for m in r.methods if m in {"GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"}))
        print(f" - {r.rule:30} | {methods:18} | {r.endpoint}")
except Exception:
    print("!! No se pudo listar rutas Flask:")
    traceback.print_exc()
PY
} >> "$OUTFILE" || true

# Copia comprimida (por si pesa mucho)
gzip -c "$OUTFILE" > "${OUTFILE}.gz" || true

echo "✅ Snapshot generado:"
echo "   Archivo:  $OUTFILE"
echo "   Copia gz: ${OUTFILE}.gz"
echo "   Ábrelo desde la app 'Archivos' → Descargas/Downloads."
