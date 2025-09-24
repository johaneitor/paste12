#!/usr/bin/env bash
set -Eeuo pipefail

echo "➤ Escribo backend/entry.py (WSGI estable)"
mkdir -p backend
cat > backend/entry.py <<'PY'
from backend import create_app  # usa tu factory existente
try:
    # blueprint del frontend (sirve /, /js/*, /css/*, robots, favicon, etc.)
    from backend.webui import webui
except Exception:
    webui = None

app = create_app()
if webui is not None:
    try:
        app.register_blueprint(webui)
    except Exception:
        pass
PY

echo "➤ Escribo Procfile (Render usará este comando)"
cat > Procfile <<'TXT'
web: gunicorn -w 2 -k gthread -b 0.0.0.0:$PORT backend.entry:app
TXT

echo "➤ Smoke local con gunicorn (si está disponible)"
if command -v gunicorn >/dev/null 2>&1; then
  pkill -9 -f gunicorn 2>/dev/null || true
  nohup gunicorn -b 127.0.0.1:8000 backend.entry:app >/dev/null 2>&1 & echo $! > /tmp/p12_guni.pid
  sleep 2
  for p in / "/js/app.js" "/css/styles.css" "/robots.txt" "/api/health"; do
    echo "--- $p"
    curl -sSI "http://127.0.0.1:8000$p" | head -n 12 || true
  done
  kill "$(cat /tmp/p12_guni.pid 2>/dev/null || echo)" 2>/dev/null || true
else
  echo "(!) gunicorn no está instalado localmente; omito smoke local."
fi

echo "➤ Commit & push"
git add Procfile backend/entry.py
git commit -m "chore(deploy): Procfile + entry WSGI (backend.entry:app) y registro seguro del frontend"
git push origin main

echo "✓ Listo. Al aplicar el deploy, Render usará backend.entry:app"
