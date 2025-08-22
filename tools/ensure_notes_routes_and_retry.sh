#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
RUNFILE="run.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="${TMPDIR}/paste12_server.log"
SERVER="http://127.0.0.1:8000"

mkdir -p "$TMPDIR"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Detectar si hay Blueprint 'api'
has_bp = False
bp_name = None
for m in re.finditer(r'(\w+)\s*=\s*Blueprint\(\s*[\'"]api[\'"]', s):
    has_bp = True
    bp_name = m.group(1)
    break

# Helpers para comprobar si ya hay decoradores adecuados
def has_decorator(text, func_name, method, rule_suffix):
    # Busca @api.route("/notes", methods=["GET"]) o @api.get("/notes") etc.
    pat = rf'@.*\.(route|get|post)\s*\(\s*[\'"]{rule_suffix}[\'"]\s*(?:,\s*methods\s*=\s*\[[^\]]*{method}[^\]]*\])?\s*\)\s*\ndef\s+{func_name}\s*\('
    return re.search(pat, text) is not None

def insert_decorator(text, func_name, decorator_line):
    # Inserta decorador justo antes de def func_name
    return re.sub(rf'(\n)(\s*)def\s+{func_name}\s*\(',
                  r'\1' + decorator_line + r'\n\2def ' + func_name + '(',
                  text, count=1)

# Determinar qué prefijo usar en la regla
if has_bp:
    # Con blueprint: la regla debe ser "/notes" y el BP tendrá url_prefix="/api"
    rule_get = "/notes"
    rule_post = "/notes"
    deco_get = f"@{bp_name}.route(\"{rule_get}\", methods=[\"GET\"])"
    deco_post = f"@{bp_name}.route(\"{rule_post}\", methods=[\"POST\"])"
else:
    # Sin blueprint: usar rutas completas
    rule_get = "/api/notes"
    rule_post = "/api/notes"
    deco_get = f"@app.route(\"{rule_get}\", methods=[\"GET\"])"
    deco_post = f"@app.route(\"{rule_post}\", methods=[\"POST\"])"

# Asegurar decorador GET para list_notes
if not has_decorator(s, "list_notes", "GET", "/notes" if has_bp else "/api/notes"):
    s = insert_decorator(s, "list_notes", deco_get)

# Asegurar decorador POST para create_note
if not has_decorator(s, "create_note", "POST", "/notes" if has_bp else "/api/notes"):
    s = insert_decorator(s, "create_note", deco_post)

Path("backend/routes.py").write_text(s, encoding="utf-8")
print("Decoradores de /notes GET/POST asegurados usando", ("Blueprint '"+bp_name+"'" if has_bp else "app.route"))
PY

# Reinicio limpio
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python "$RUNFILE" >"$LOG" 2>&1 & disown || true
sleep 2

# Smokes
echo ">>> SMOKES"
curl -sS -o /dev/null -w "health=%{http_code}\n" "$SERVER/api/health"
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" "$SERVER/api/notes"
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" -d '{"text":"nota desde ensure routes","hours":24}' "$SERVER/api/notes"

# URL map pequeño para ver qué quedó registrado
python - <<'PY'
from run import app
rules = []
for r in app.url_map.iter_rules():
    if "/api" in r.rule or "notes" in r.rule or "health" in r.rule:
        rules.append((r.rule, sorted(list(r.methods)), r.endpoint))
rules.sort()
print(">>> URL MAP (parcial):")
for rule, methods, ep in rules:
    print(f" {rule:28s}  {methods}  {ep}")
PY

echo "Log: $LOG (usa: tail -n 160 \"$LOG\")"
