#!/usr/bin/env bash
set -euo pipefail

INIT="backend/__init__.py"
[[ -f "$INIT" ]] || { echo "No existe $INIT"; exit 1; }

# importar api_bp si falta
if ! grep -q "from backend.routes import api as api_bp" "$INIT"; then
  awk '
    BEGIN{done=0}
    {
      if(!done && $0 ~ /^def[ \t]+create_app\(/){
        print "from backend.routes import api as api_bp"
        done=1
      }
      print $0
    }
  ' "$INIT" > "$INIT.tmp" && mv "$INIT.tmp" "$INIT"
  echo "Añadido import api_bp"
fi

# registrar blueprint si falta
python - "$INIT" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1]); s=p.read_text(encoding="utf-8")
if "from backend.routes import api as api_bp" in s and "register_blueprint(api_bp" not in s:
    s=re.sub(r"(def create_app\([^\)]*\):\n)", r"\1    app.register_blueprint(api_bp, url_prefix='/api')\n", s, count=1)
    p.write_text(s, encoding="utf-8"); print("Añadido app.register_blueprint(api_bp, url_prefix='/api')")
else:
    print("Blueprint ya registrado o falta import api_bp")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(api): asegura registro de blueprint api en create_app()" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "→ Hecho."
