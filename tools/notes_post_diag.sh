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
path=sys.argv[1]
s=open(path,'r',encoding='utf-8').read()

m=re.search(r'(?m)^([ \t]*)def\s+create_note\s*\(\)\s*:\s*\n', s)
if not m:
    print("[!] No encontré def create_note() en routes.py — nada que parchear")
    sys.exit(0)

indent = m.group(1)
indent2 = indent + "    "
indent3 = indent2 + "    "

# localizar fin de la función (siguiente def o decorador al mismo nivel)
pos=m.end()
m_next=re.search(r'(?m)^(%s(?:def|@))' % re.escape(indent), s[pos:])
end = pos + m_next.start() if m_next else len(s)

new_func = (
    indent + "def create_note():\n" +
    indent2 + "from flask import request, jsonify\n" +
    indent2 + "from datetime import timedelta\n" +
    indent2 + "data = request.get_json(silent=True) or {}\n" +
    indent2 + "text = (data.get('text') or '').strip()\n" +
    indent2 + "if not text:\n" +
    indent3 + "return jsonify({'error':'text required'}), 400\n" +
    indent2 + "try:\n" +
    indent3 + "hours = int(data.get('hours', 24))\n" +
    indent2 + "except Exception:\n" +
    indent3 + "hours = 24\n" +
    indent2 + "hours = min(168, max(1, hours))\n" +
    indent2 + "now = _now()\n" +
    indent2 + "try:\n" +
    indent3 + "n = Note(text=text, timestamp=now, expires_at=now + timedelta(hours=hours))\n" +
    indent3 + "try:\n" +
    indent3 + "    # Fallback si el hook no setea author_fp\n" +
    indent3 + "    if not getattr(n, 'author_fp', None):\n" +
    indent3 + "        from backend.utils.fingerprint import client_fingerprint\n" +
    indent3 + "        n.author_fp = client_fingerprint()\n" +
    indent3 + "except Exception:\n" +
    indent3 + "    pass\n" +
    indent3 + "db.session.add(n)\n" +
    indent3 + "db.session.commit()\n" +
    indent3 + "return jsonify(_note_json(n, now)), 201\n" +
    indent2 + "except Exception as e:\n" +
    indent3 + "db.session.rollback()\n" +
    indent3 + "import traceback\n" +
    indent3 + "tb = traceback.format_exc()\n" +
    indent3 + "try:\n" +
    indent3 + "    from flask import current_app\n" +
    indent3 + "    current_app.logger.error('create_note failed: %s', tb)\n" +
    indent3 + "except Exception:\n" +
    indent3 + "    pass\n" +
    indent3 + "return jsonify({'error':'create_failed','detail':str(e),'trace':tb}), 500\n"
)

s = s[:m.start()] + new_func + s[end:]
open(path,'w',encoding='utf-8').write(s)
print("[OK] create_note ahora devuelve JSON detallado ante error.")
PY

# Reinicio y smokes
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] URL MAP (resumen):"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules):
    if rule.startswith("/api/notes"):
        print(f"{rule:35s} {','.join(methods):10s}  {ep}")
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke POST /api/notes (veremos JSON de error si falla)"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-diag","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,200p'

echo
echo "[+] Tail logs (.tmp/paste12.log)"
tail -n 120 "$LOG" || true
