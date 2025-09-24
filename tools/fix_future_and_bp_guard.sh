#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Backups"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true
cp "$RUNPY"  "$RUNPY.bak.$(date +%s)"   2>/dev/null || true

# --- 1) Mover "from __future__ import annotations" al tope (respetando docstring) ---
python - "$ROUTES" <<'PY'
import re,sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Quitar cualquier futuro import duplicado
s = re.sub(r'(?m)^\s*from\s+__future__\s+import\s+annotations\s*\n', '', s)

lines = s.splitlines(True)

# Saltar shebang/encoding/comments iniciales para detectar docstring
i = 0
while i < len(lines) and (lines[i].strip()=='' or lines[i].lstrip().startswith('#')):
    i += 1

insert_at = 0
if i < len(lines) and re.match(r'^\s*(?P<q>"""|\'\'\')', lines[i]):
    q = re.match(r'^\s*(?P<q>"""|\'\'\')', lines[i]).group('q')
    j = i+1
    closed=False
    while j < len(lines):
        if q in lines[j]:
            closed=True
            j += 1
            break
        j += 1
    insert_at = j if closed else i
else:
    insert_at = i

lines.insert(insert_at, 'from __future__ import annotations\n')
open(p,'w',encoding='utf-8').write(''.join(lines))
print("[OK] routes.py: future import colocado al inicio.")
PY

# --- 2) Proteger el registro del blueprint en run.py (evita 'already registered') ---
python - "$RUNPY" <<'PY'
import re,sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

if 'register_blueprint(api_bp' in s and 'if "api" not in app.blueprints' not in s:
    # Extrae url_prefix si está
    m = re.search(r'app\.register_blueprint\(\s*api_bp\s*(?:,\s*url_prefix\s*=\s*(?P<up>"[^"]*"|\'[^\']*\'))?\s*\)', s)
    if m:
        up = m.group('up') or '"\\/api"'
        guard = f'if "api" not in app.blueprints:\n    app.register_blueprint(api_bp, url_prefix={up})'
        s = re.sub(r'app\.register_blueprint\(\s*api_bp\s*(?:,\s*url_prefix\s*=\s*(?:"[^"]*"|\'[^\']*\'))?\s*\)', guard, s, count=1)
        open(p,'w',encoding='utf-8').write(s)
        print('[OK] run.py: agregado guard al registrar blueprint.')
    else:
        print('[i] run.py: no encontré patrón clásico de register_blueprint; sin cambios.')
else:
    print('[i] run.py: ya estaba protegido o no registra api_bp explícitamente.')
PY

# --- 3) Reiniciar y probar ---
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2

echo "[+] Tail log:"
tail -n 40 "$LOG" || true

echo "[+] URL MAP (notas):"
python - <<'PY'
import importlib
mod = importlib.import_module("run")
app = getattr(mod, "app", None)
for r in sorted(app.url_map.iter_rules(), key=lambda x: str(x)):
    meth = ",".join(sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")))
    if "/notes" in str(r):
        print(f"{str(r):35s} {meth:8s} {r.endpoint}")
# Chequeos rápidos
rules = list(app.url_map.iter_rules())
has_get = any(str(r) == "/api/notes" and "GET" in r.methods for r in rules)
has_post= any(str(r) == "/api/notes" and "POST" in r.methods for r in rules)
print(f"CHECK  /api/notes GET:{has_get}  POST:{has_post}")
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-future-fix","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
