#!/usr/bin/env bash
set -Eeuo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="${PREFIX}/tmp/paste12_server.log"

echo "➤ Tail log previo (si existe):"
[ -f "$LOG" ] && tail -n 120 "$LOG" || echo "(no hay log previo)"

echo "➤ Comprobando config de DB real desde run.py"
python - <<'PY'
try:
    from run import app
    print("DB URI:", app.config.get("SQLALCHEMY_DATABASE_URI"))
except Exception as e:
    print("Import run error:", e)
PY

echo "➤ PIDs previos:"
ps -o pid,cmd | grep -E 'python .*run\.py' | grep -v grep || true

echo "➤ Reinicio en limpio"
pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Tail log tras relanzar:"
tail -n 160 "$LOG" || true

echo "➤ Probar endpoints:"
for u in /api/health /api/notes; do
  printf "%-14s -> " "$u"
  curl -sS -m 6 -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:8000$u"
done

echo "➤ Si murió de nuevo, ejecuta en primer plano para ver el stack completo:"
echo "    python run.py"
