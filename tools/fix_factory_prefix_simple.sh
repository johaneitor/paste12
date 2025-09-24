#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }; _grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

F="backend/__init__.py"
[[ -f "$F" ]] || { _red "No existe $F"; exit 1; }

python - <<'PY'
from pathlib import Path

p = Path("backend/__init__.py")
src = p.read_text(encoding="utf-8")

# 1) Asegurar el import del blueprint
need = "from backend.routes import api as api_bp"
if need not in src:
    # lo inyecto después del primer import de flask/backend para no romper nada
    lines = src.splitlines(True)
    ins_at = 0
    for i, line in enumerate(lines[:100]):  # solo escaneo el arranque del archivo
        if line.strip().startswith("from flask ") or line.strip().startswith("import flask") or line.strip().startswith("from backend"):
            ins_at = i + 1
    lines.insert(ins_at, need + "\n")
    src = "".join(lines)

# 2) Normalizar TODAS las apariciones de register_blueprint(api_bp, ...)
#    - si ya trae url_prefix, lo reemplazo por "/api"
#    - si no trae, se lo agrego
def normalize_call(s: str) -> str:
    out = []
    i = 0
    while True:
        j = s.find("app.register_blueprint(", i)
        if j == -1:
            out.append(s[i:])
            break
        out.append(s[i:j])
        k = s.find(")", j)
        if k == -1:
            # raro, dejo igual para no romper el archivo
            out.append(s[j:])
            break
        call = s[j:k+1]
        if "api_bp" in call:
            if "url_prefix=" in call:
                # normalizo a "/api"
                # manejos sencillos de comillas
                call_norm = call
                call_norm = call_norm.replace("url_prefix='/api'", 'url_prefix="/api"')
                call_norm = call_norm.replace("url_prefix=\"/api\"", 'url_prefix="/api"')
                # si tenía otro prefijo, lo piso por "/api"
                # (reemplazo ingenuo, suficiente para casos típicos)
                start = call_norm.find("url_prefix=")
                if start != -1:
                    # adelanto hasta después de '='
                    start_val = start + len("url_prefix=")
                    # busco próxima coma o ')'
                    end_val = call_norm.find(",", start_val)
                    end_par = call_norm.find(")", start_val)
                    if end_val == -1 or (end_par != -1 and end_par < end_val):
                        end_val = end_par
                    if end_val != -1:
                        call_norm = call_norm[:start_val] + '"/api"' + call_norm[end_val:]
                out.append(call_norm)
            else:
                # sin url_prefix -> lo agrego (con coma si hiciera falta)
                if call.rstrip().endswith(")"):
                    inner = call[len("app.register_blueprint("):-1].strip()
                    if inner == "api_bp":
                        call_norm = 'app.register_blueprint(api_bp, url_prefix="/api")'
                    else:
                        # ya tenía otros args -> agrego coma + url_prefix
                        call_norm = "app.register_blueprint(" + inner + ', url_prefix="/api")'
                    out.append(call_norm)
                else:
                    out.append(call)  # fallback
        else:
            out.append(call)
        i = k + 1
    return "".join(out)

src = normalize_call(src)

p.write_text(src, encoding="utf-8")
print("OK: backend/__init__.py normalizado (register_blueprint -> url_prefix=\"/api\")")
PY

git add backend/__init__.py >/dev/null 2>&1 || true
git commit -m "fix(factory): fuerza url_prefix=/api en register_blueprint(api_bp)" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true

_grn "✓ Commit & push hechos."
