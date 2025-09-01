set -euo pipefail
export PORT="${PORT:-8000}"
python - <<'PY'
import importlib.util, subprocess, sys
pkgs = ["waitress","sqlalchemy","flask","flask-cors","asgiref"]
missing = [p for p in pkgs if importlib.util.find_spec(p) is None]
if missing:
    print("Instalando:", " ".join(missing))
    subprocess.check_call([sys.executable,"-m","pip","install","-q",*missing])
else:
    print("Dependencias OK")
PY
is_termux=0
case "${PREFIX-}" in */com.termux/*) is_termux=1;; esac
if [ -z "${APP_MODULE-}" ]; then
  if out="$(scripts/auto_try_app_module.sh 2>/dev/null || true)"; then
    if [ -n "$out" ]; then export APP_MODULE="$out"; echo "[serve] APP_MODULE detectado → $APP_MODULE"; fi
  fi
fi
[ -z "${APP_MODULE-}" ] && { echo "APP_MODULE no definido/detectable. Ej: export APP_MODULE='wsgiapp:app'"; exit 2; }
if [ $is_termux -eq 1 ]; then
  echo "[serve] Termux → Waitress"
  python - <<PY
from waitress import serve
import os, patched_app as pa
serve(pa.app, host="0.0.0.0", port=int(os.environ.get("PORT","8000")))
PY
else
  echo "[serve] Linux → Gunicorn gthread"
  cat > gunicorn_conf.py <<'PY'
import os
bind = f"0.0.0.0:{os.environ.get('PORT','8000')}"
workers = int(os.environ.get("WORKERS", 1))
worker_class = os.environ.get("WCLASS","gthread")
threads = int(os.environ.get("THREADS","2"))
timeout = int(os.environ.get("TIMEOUT","90"))
graceful_timeout = int(os.environ.get("GRACEFUL","30"))
keepalive = int(os.environ.get("KEEPALIVE","5"))
preload_app = False
loglevel = os.environ.get("LOGLEVEL","info")
errorlog = "-"
accesslog = "-"
PY
  exec gunicorn -c gunicorn_conf.py 'patched_app:app'
fi
