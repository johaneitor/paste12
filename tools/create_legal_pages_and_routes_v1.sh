#!/usr/bin/env bash
set -euo pipefail
PUB="${1:-ca-pub-9479870293204581}"

# --- 1) Frontend: páginas mínimas ---
mkdir -p frontend
mk() {
  local f="frontend/$1.html"
  if [[ ! -f "$f" ]]; then
    cat > "$f" <<HTML
<!doctype html><meta charset="utf-8">
<title>Paste12 - ${1^}</title>
<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=$PUB" crossorigin="anonymous"></script>
<style>body{font:16px/1.5 system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:60rem}</style>
<h1>${1^}</h1>
<p>Documento ${1} de Paste12. Versión mínima.</p>
HTML
    echo "Creado: $f"
  else
    echo "OK: $f ya existe"
  fi
}
mk terms
mk privacy

# --- 2) Backend: rutas para servirlas ---
ROUTES="backend/routes.py"
[[ -f "$ROUTES" ]] || { echo "ERROR: falta $ROUTES"; exit 2; }

python - <<'PY'
import io,re
p="backend/routes.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s
if "from flask import send_from_directory" not in s:
    s=s.replace("from flask import","from flask import send_from_directory, ",1)

def ensure_route(name):
    rx=rf"@app\.route\('/{name}'"
    if re.search(rx,s): return s
    s2 = (
        f"\n\n@app.route('/{name}', methods=['GET','HEAD'])\n"
        f"def {name}():\n"
        f"    return send_from_directory('frontend','{name}.html')\n"
    )
    return s+s2

s=ensure_route("terms")
s=ensure_route("privacy")

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[routes] añadidas /terms y /privacy")
else:
    print("[routes] ya estaban")

PY

python -m py_compile backend/routes.py && echo "py_compile routes OK"
echo "Hecho. Recuerda hacer deploy."
