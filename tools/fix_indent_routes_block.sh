#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
from pathlib import Path, re
p=Path("backend/routes.py")
s=p.read_text(encoding="utf-8")

def lift(pattern_header, def_name):
    global s
    s = re.sub(
        rf'(?m)^[ \t]+@api\.route\({pattern_header}[^\n]*\)\s*\n[ \t]+def\s+{def_name}\(',
        f'@api.route({pattern_header}, methods=["GET"])\ndef {def_name}(',
        s
    )

lift(r'"/_routes"', "api_routes_dump")
lift(r'"/routes"', "api_routes_dump_alias")
lift(r'"/ping"', "api_ping")

s = s.replace("\t","    ")
p.write_text(s, encoding="utf-8")
print("OK: normalizado indent de ping/_routes/routes")
PY
git add backend/routes.py >/dev/null 2>&1 || true
git commit -m "fix(api): normaliza indent de /api/ping y /api/_routes" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "Hecho."
