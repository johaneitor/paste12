#!/usr/bin/env bash
set -Eeuo pipefail

LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"

echo "➤ Kill posibles procesos previos"
pkill -9 -f "python .*run\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true

echo "➤ Chequeo de sintaxis en backend/__init__.py y backend/webui.py"
python - <<'PY'
import traceback, sys
files = ["backend/__init__.py", "backend/webui.py"]
ok = True
for f in files:
    try:
        with open(f, "rb") as fh:
            compile(fh.read(), f, "exec")
        print(f"[OK] syntax: {f}")
    except Exception:
        ok = False
        print(f"[ERR] syntax: {f}")
        traceback.print_exc()
if not ok:
    sys.exit(2)
PY

echo "➤ Arrancando run.py en background (log: $LOG)"
mkdir -p "$(dirname "$LOG")"
nohup python -u run.py >"$LOG" 2>&1 & echo "PID=$!"
sleep 2

echo "➤ Smoke /api/health"
code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health || true)"
echo "health=$code"
if [ "$code" != "200" ]; then
  echo "— Últimas 120 líneas de $LOG —"
  tail -n 120 "$LOG" || true
  echo "— Fin del log —"
  exit 1
fi

echo "➤ Rutas clave (si se puede importar la app)"
python - <<'PY'
import traceback
try:
    from run import app
    got = {r.rule: sorted(m for m in r.methods if m not in {"HEAD","OPTIONS"}) for r in app.url_map.iter_rules()}
    for k in ["/", "/js/<path:fname>", "/css/<path:fname>", "/robots.txt", "/api/_routes", "/api/health"]:
        print(f"{k}: {'OK' if k in got else 'NO'}", got.get(k))
except Exception:
    traceback.print_exc()
PY
