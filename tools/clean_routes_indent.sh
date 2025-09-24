#!/usr/bin/env bash
set -euo pipefail
_red(){ printf "\033[31m%s\033[0m\n" "$*"; }
_grn(){ printf "\033[32m%s\033[0m\n" "$*"; }

FILE="backend/routes.py"
[[ -f "$FILE" ]] || { _red "No existe $FILE"; exit 1; }

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
src = p.read_text(encoding="utf-8")

# 0) normalizar fin de línea y tabs
src = src.replace("\r\n","\n").replace("\r","\n").replace("\t","    ")

# 1) quitar cualquier DEF _to(...) + su bloque indentado
#    - empieza en cualquier col (^\s*def _to(...)
#    - consume líneas siguientes que estén más indentadas que su inicio
def rm_block(pattern, s):
    pat = re.compile(pattern, re.M)
    while True:
        m = pat.search(s)
        if not m: break
        start = m.start()
        # indent de la línea def
        line_start = s.rfind("\n", 0, start) + 1
        indent = len(s[line_start:start]) - len(s[line_start:start].lstrip(" "))
        # avanzar hasta la primera línea con indent <= indent de def y no vacía
        i = m.end()
        while i < len(s):
            j = s.find("\n", i)
            if j == -1: j = len(s)
            line = s[i:j]
            if line.strip():  # si no es en blanco
                cur_indent = len(line) - len(line.lstrip(" "))
                if cur_indent <= indent:
                    break
            i = j + 1
        s = s[:line_start] + "\n" + s[i:]  # dejar una línea en blanco donde estaba
    return s

src = rm_block(r'(?m)^\s*def\s+_to\s*\(', src)

# 2) arreglar imports indentados comunes
src = re.sub(r'(?m)^\s+from flask import jsonify\s*$', 'from flask import jsonify', src)
src = re.sub(r'(?m)^\s+from flask import (current_app|send_from_directory)\s*$', r'from flask import \1', src)
src = re.sub(r'(?m)^\s+import sqlalchemy as sa\s*$', 'import sqlalchemy as sa', src)

# 3) blueprint: asegurar única forma sin url_prefix aquí
src = re.sub(r'(?m)^\s*api\s*=\s*Blueprint\(\s*["\']api["\']\s*,\s*__name__\s*,\s*url_prefix\s*=\s*["\'][^"\']+["\']\s*\)\s*$',
             'api = Blueprint("api", __name__)', src)
# si hay duplicadas, deja la primera "bonita"
lines = [ln for ln in src.split("\n") if not re.match(r'^\s*api\s*=\s*Blueprint\(', ln)]
# volver a insertar una sola declaración (si no quedó ninguna)
if 'api = Blueprint("api", __name__)' not in "\n".join(lines):
    # ponerla justo después del primer bloque de imports de flask/stdlib
    s2 = "\n".join(lines)
    m = re.search(r'(?m)^(?:from|import).*\n(?:from|import).*\n*', s2)
    if m:
        pos = m.end()
        s2 = s2[:pos] + 'api = Blueprint("api", __name__)\n' + s2[pos:]
    else:
        s2 = 'from flask import Blueprint\napi = Blueprint("api", __name__)\n' + s2
    src = s2
else:
    src = "\n".join(lines)
    # volver a poner una "bonita" arriba del archivo tras imports
    m = re.search(r'(?m)^(?:from|import).*\n(?:from|import).*\n*', src)
    if m:
        pos = m.end()
        src = src[:pos] + 'api = Blueprint("api", __name__)\n' + src[pos:]
    else:
        src = 'from flask import Blueprint\napi = Blueprint("api", __name__)\n' + src

# 4) compactar múltiples líneas en blanco
src = re.sub(r'\n{3,}', '\n\n', src).strip() + "\n"

p.write_text(src, encoding="utf-8")
print("OK: routes.py limpiado")
PY

git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "hotfix(routes): elimina bloque _to() residual y normaliza imports/blueprint" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
_grn "✓ Commit & push hechos."
