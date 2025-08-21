#!/usr/bin/env bash
set -Eeuo pipefail
outfile="app_snapshot_$(date +%Y%m%d_%H%M%S).txt"

echo "### SNAPSHOT @ $(date -Iseconds)" > "$outfile"

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
  echo "===== LISTA COMPLETA DE ARCHIVOS DE CÓDIGO ====="
  find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.css' -o -name 'Dockerfile' -o -name 'Procfile' -o -name '*.yml' -o -name '*.yaml' -o -name 'render.yaml' -o -name 'render.yml' -o -name 'requirements.txt' \) \
    -not -path './.git/*' -not -path './venv/*' -not -path './.venv/*' -not -path './instance/*' -not -path './backups_*/*' \
    | sort

  echo
  echo "===== CONTENIDO DE ARCHIVOS DE CÓDIGO ====="
} >> "$outfile"

# recopilar contenidos
while IFS= read -r f; do
  echo -e "\n----- BEGIN FILE: $f -----" >> "$outfile"
  sed -n '1,200000p' "$f" >> "$outfile" || echo "[[ no se pudo leer $f ]]" >> "$outfile"
  echo -e "----- END FILE: $f -----" >> "$outfile"
done < <(find . -type f \( -name '*.py' -o -name '*.js' -o -name '*.html' -o -name '*.css' -o -name 'Dockerfile' -o -name 'Procfile' -o -name '*.yml' -o -name '*.yaml' -o -name 'render.yaml' -o -name 'render.yml' -o -name 'requirements.txt' \) \
    -not -path './.git/*' -not -path './venv/*' -not -path './.venv/*' -not -path './instance/*' -not -path './backups_*/*' \
    | sort)

# resumen de rutas Flask (opcional; ignora errores)
{
  echo
  echo "===== FLASK URL MAP (opcional) ====="
  python - <<'PY'
import os, sys, traceback
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app
    app = create_app()
    print("static_folder:", getattr(app, "static_folder", None))
    print("\nRutas registradas:")
    rules = sorted(app.url_map.iter_rules(), key=lambda r: (r.rule, ",".join(sorted(r.methods))))
    for r in rules:
        methods = ",".join(sorted(m for m in r.methods if m in {"GET","POST","PUT","DELETE","PATCH","HEAD","OPTIONS"}))
        print(f" - {r.rule:30} | {methods:18} | {r.endpoint}")
except Exception:
    print("!! No se pudo listar rutas Flask:")
    traceback.print_exc()
PY
} >> "$outfile" || true

echo "✅ Snapshot generado:"
echo "   $outfile"
echo "   (Si pesa mucho, puedes comprimirlo:  gzip -9 $outfile )"
