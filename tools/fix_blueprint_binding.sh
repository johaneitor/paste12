#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

[ -f "$ROUTES" ] || { echo "[!] No encuentro $ROUTES"; exit 1; }

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re,sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# 1) Detectar variable de Blueprint (api, API, bp, etc.)
bp=None
m=re.search(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*Blueprint\(', s)
if m:
    bp=m.group(1)
else:
    # fallback: inspeccionar decoradores existentes distintos de "app"
    m=re.search(r'(?m)^\s*@([A-Za-z_][A-Za-z0-9_]*)\.route\(', s)
    if m and m.group(1)!='app':
        bp=m.group(1)

if not bp:
    print("[!] No encontré Blueprint en routes.py; no toco nada.")
    open(p,'w',encoding='utf-8').write(s)
    sys.exit(0)

print("[OK] Blueprint detectado:", bp)

# 2) Reescribir SOLO los decoradores de /api/notes que usen @app.route(...)
pat = re.compile(r'(?m)^\s*@app\.route\(\s*(["\'])/api/notes\1\s*,\s*methods\s*=\s*\[([^\]]+)\]\s*\)')
def repl(m):
    return f"@{bp}.route('/api/notes', methods=[{m.group(2)}])"
s, n = pat.subn(repl, s)
print(f"[OK] Decoradores /api/notes convertidos: {n}")

# 3) Validación rápida: no debería quedar ningún @app.route residual
# (si hubiera, mejor avisar para que no dispare NameError)
if re.search(r'(?m)^\s*@app\.route\(', s):
    print("[!] Aún quedan @app.route(...) en routes.py (que no son /api/notes). Revísalos o conviértelos al blueprint.")

open(p,'w',encoding='utf-8').write(s)
PY

# 4) Reiniciar y mostrar logs
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 60 "$LOG" || true

# 5) Smoke local
PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"
echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"probe-fix-bp","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,80p'
echo

# 6) Push para redeploy en Render
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix(routes): bind /api/notes to actual Blueprint (no @app.route)" || true
  git push -u --force-with-lease origin "$BRANCH" || echo "[!] Push falló (revisa remoto/credenciales)."
fi
