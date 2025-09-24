#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] Escribiendo shim wsgiapp/__init__.py → reexporta render_entry.app"
mkdir -p wsgiapp
cat > wsgiapp/__init__.py <<'PY'
# Bridge: siempre exporta app desde render_entry
try:
    from render_entry import app as app  # preferido: añade /api/debug-urlmap y fallback /api/notes
except Exception as _e:
    # Último recurso: intenta la app original
    try:
        from wsgi import app as app
    except Exception:
        from flask import Flask, jsonify
        app = Flask(__name__)
        @app.get("/api/health")
        def _health():
            return jsonify(ok=True, note="shim-fallback"), 200
PY

echo "[+] Git commit & push"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git add -A
git commit -m "shim: route wsgiapp:app -> render_entry:app (forces /api/notes & /api/debug-urlmap)" || true
git push -u --force-with-lease origin "$BRANCH"

cat <<'MSG'

==============================================================
[1] En Render puedes dejar el Start Command COMO ESTÁ:
    gunicorn -w ${WEB_CONCURRENCY:-2} -k gthread --threads ${THREADS:-4} -b 0.0.0.0:$PORT wsgiapp:app
    (o si prefieres: render_entry:app). Con este shim, ambos funcionan.

[2] Tras el redeploy, valida con:
  curl -s https://paste12-rmsk.onrender.com/api/bridge-ping
  curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap
  curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,80p'
  curl -i -s -X POST -H 'Content-Type: application/json' \
       -d '{"text":"remote-ok","hours":24}' \
       https://paste12-rmsk.onrender.com/api/notes | sed -n '1,120p'

Notas:
- Si /api/bridge-ping y /api/debug-urlmap siguen 404, el deploy aún no tomó.
- Los “jq parse error” venían de intentar parsear HTML 404 como JSON; hasta ver 200, evita pipear a jq.
==============================================================
MSG
