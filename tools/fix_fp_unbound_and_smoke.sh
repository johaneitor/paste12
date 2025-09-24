#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# 1) Asegurar que existe _fp(); si no, crear un fallback muy simple
if not re.search(r'(?m)^def\s+_fp\s*\(\)\s*->?\s*str\s*:', s):
    s = re.sub(r'(?m)^', '', s, count=0)
    s = "def _fp() -> str:\n    return 'noctx'\n\n" + s

# 2) Quitar imports de client_fingerprint (para evitar sombras locales)
s = re.sub(r'(?m)^\s*from\s+backend\.utils\.fingerprint\s+import\s+client_fingerprint\s*\n', '', s)

# 3) Reemplazar cualquier uso de client_fingerprint() por _fp()
s = re.sub(r'\bclient_fingerprint\s*\(\s*\)', r'_fp()', s)

# Guardar
open(p,'w',encoding='utf-8').write(s)
print("[OK] routes.py: uso de fingerprint unificado a _fp() y sin imports locales problemáticos.")
PY

echo "[+] Reinicio local"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] URL MAP /api/notes"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
for r in sorted(app.url_map.iter_rules(), key=lambda r: str(r)):
    if str(r).startswith("/api/notes"):
        ms=",".join(sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")]))
        print(f"{str(r):35s} {ms:10s} {r.endpoint}")
PY

echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"post-after-fp-fix","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'

echo
echo "[+] Tail logs"
tail -n 120 "$LOG" || true
