#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py"); s = p.read_text(encoding="utf-8")

# Inserta print de diagnóstico dentro de list_notes (después de calcular page)
s = re.sub(
    r'(def\s+list_notes\s*\(\)\s*:\s*[\s\S]*?items\s*=\s*q\.limit\(.*?\)\.all\(\)\s*?\n\s*page\s*=\s*items\[:limit\]\s*\n)',
    r"\1        print(f\"[list_notes] after_id={after_id!r} limit={limit} items_len={len(items)} page_len={len(page)} next_cursor={(page[-1].id if page else None)}\", flush=True)\n",
    s, flags=re.S
)

# Asegura que devolvemos solo page y seteamos header solo si hay siguiente
s = re.sub(
    r'resp\s*=\s*jsonify\(\[.*?for\s+n\s+in\s+page\]\)',
    r'resp = jsonify([to_dict(n) for n in page])',
    s
)
s = re.sub(
    r'if\s+len\(items\)\s*>\s*limit\s*and\s*page\s*:\s*\n\s*resp\.headers\["X-Next-After"\]\s*=\s*str\(page\[-1\]\.id\)',
    r'if len(items) > limit and page:\n            resp.headers["X-Next-After"] = str(page[-1].id)',
    s
)

Path("backend/routes.py").write_text(s, encoding="utf-8")
print("routes.py instrumentado con prints de diagnóstico.")
PY

echo "➤ Restart"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Crear 3 notas para forzar 2+ páginas"
for i in 1 2 3; do
  curl -sS -H "Content-Type: application/json" -d '{"text":"diag paginación","hours":24}' http://127.0.0.1:8000/api/notes >/dev/null
done

echo "➤ limit=2 (len debe ser 2)"
curl -sS 'http://127.0.0.1:8000/api/notes?limit=2' | python - <<'PY'
import sys, json; 
try:
    data = json.load(sys.stdin)
    print(len(data))
except Exception as e:
    print("JSON parse error:", e)
PY

echo "➤ Header X-Next-After esperado si hay más"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | sed -n '/^X-Next-After:/Ip'

echo "➤ Últimas líneas del log (diagnóstico list_notes)"
tail -n 80 "$LOG" | sed -n '/\[list_notes\]/,$p' || true

echo "➤ (Opcional) commit"
git add backend/routes.py || true
git commit -m "chore(api): instrumentar list_notes con prints de diagnóstico de paginación" || true
