#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Backup de run.py"
cp "$RUNPY" "$RUNPY.bak.$(date +%s)" 2>/dev/null || true

python - "$RUNPY" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read().replace('\r\n','\n')

# 1) Eliminar TODAS las líneas existentes con register_blueprint(api_bp, ...)
s = re.sub(r'(?m)^\s*app\.register_blueprint\(\s*api_bp\b[^\n]*\n', '', s)

# 2) Normalizar cualquier guard viejo mal formateado
guard = 'if "api" not in app.blueprints:\n    app.register_blueprint(api_bp, url_prefix="/api")\n'
s = re.sub(
    r'(?ms)^\s*if\s+"api"\s+not\s+in\s+app\.blueprints\s*:\s*\n\s*app\.register_blueprint\(\s*api_bp\b[^\n]*\)\s*',
    guard,
    s
)

# 3) Insertar el guard si no está presente luego del import de api_bp
if 'app.register_blueprint(api_bp' not in s:
    lines = s.splitlines(True)
    # buscar import canónico
    idx = None
    for i,l in enumerate(lines):
        if re.search(r'\bfrom\s+backend\.routes\s+import\s+bp\s+as\s+api_bp\b', l):
            idx = i; break
    if idx is None:
        # fallback: si no encontramos el import canónico, insertamos cerca del top
        idx = 0
    lines.insert(idx+1, guard)
    s = ''.join(lines)

open(p,'w',encoding='utf-8').write(s)
print("[OK] run.py: guard normalizado e indentado.")
PY

echo "[+] Verificando sintaxis de run.py"
python -m py_compile "$RUNPY"

echo "[+] Reiniciando app"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2
tail -n 40 "$LOG" || true

echo "[+] URL map de /api/notes"
python - <<'PY'
import importlib
mod = importlib.import_module("run")
app = getattr(mod, "app", None)
for r in sorted(app.url_map.iter_rules(), key=lambda x: str(x)):
    if "/notes" in str(r):
        methods=",".join(sorted(m for m in r.methods if m not in ("HEAD","OPTIONS")))
        print(f"{str(r):35s} {methods:8s} {r.endpoint}")
rules=list(app.url_map.iter_rules())
print("CHECK GET:", any(str(r)=="/api/notes" and "GET" in r.methods for r in rules),
      "POST:", any(str(r)=="/api/notes" and "POST" in r.methods for r in rules))
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke tests"
echo "--- GET"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-after-guard","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'
