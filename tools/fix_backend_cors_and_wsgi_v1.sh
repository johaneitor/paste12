#!/usr/bin/env bash
set -euo pipefail

# Módulos donde típicamente se usa CORS/app
TARGETS=(
  "backend/__init__.py"
  "backend/app.py"
  "backend/main.py"
  "backend/wsgi.py"
  "run.py"
)

ts="$(date -u +%Y%m%d-%H%M%SZ)"
changed=0

patch_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  cp -f "$f" "$f.$ts.bak"

  python - <<PY
import io, os, re, sys
p = sys.argv[1]
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# 1) Asegurar import de CORS sin duplicar
if "from flask_cors import CORS" not in s:
    # insertar después del primer bloque de imports
    m = re.search(r"^(from .+|import .+)$", s, re.M)
    if m:
        # buscar el último import consecutivo
        start = 0
        last = 0
        for mm in re.finditer(r"^(from .+|import .+)$", s, re.M):
            last = mm.end()
        s = s[:last] + "\nfrom flask_cors import CORS\n" + s[last:]
    else:
        s = "from flask_cors import CORS\n" + s

# 2) Añadir bloque de export WSGI 'application' si no existe
if "application = " not in s:
    trailer = "\n\n# --- auto-injected WSGI export (safe) ---\n" \
              "try:\n" \
              "    # Si existe 'app', úsalo; si no, intenta create_app()\n" \
              "    application = globals().get('app', None)\n" \
              "    if application is None and 'create_app' in globals():\n" \
              "        application = create_app()\n" \
              "except Exception as _e:\n" \
              "    # no romper import si falla; el shim intentará otras rutas\n" \
              "    pass\n"
    s += trailer

# 3) (Opcional, no intrusivo) — si ya existe 'app' y no se aplicó CORS en ningún lado,
#    intenta un CORS(app) mínimo en un bloque try/except para no romper.
if re.search(r"\\bapp\\b\\s*=\\s*Flask\\(", s) and "CORS(" not in s:
    s += "\n# --- auto-injected CORS (safe) ---\n" \
         "try:\n" \
         "    _a = globals().get('app', None)\n" \
         "    if _a:\n" \
         "        CORS(_a, resources={r\"/api/*\": {\"origins\": \"*\"}}, supports_credentials=False)\n" \
         "except Exception:\n" \
         "    pass\n"

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print(f"[patched] {p}")
else:
    print(f"[skip] {p} (sin cambios)")
PY
  python -m py_compile "$f" || {
    echo "py_compile FAIL en $f — restaurando backup"
    mv -f "$f.$ts.bak" "$f"
    return 1
  }
  ((changed+=1))
  echo "[ok] $f"
}

for f in "${TARGETS[@]}"; do
  patch_file "$f" || exit 1
done

if ((changed==0)); then
  echo "ℹ️  Nada que parchear (o ya estaba OK)."
else
  echo "✓ Parche aplicado en $changed archivo(s). Backups con sufijo .$ts.bak"
fi

echo "Siguiente paso sugerido:"
echo "  1) Desplegar en Render con el Start Command que ya usas."
echo "  2) Correr tools/smoke_after_cors_wsgi_fix_v2.sh \"https://paste12-rmsk.onrender.com\""
