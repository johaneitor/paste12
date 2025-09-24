#!/usr/bin/env bash
set -euo pipefail
cp -a render_entry.py entry_main.py
cat > wsgi.py <<'PY'
from entry_main import app as application
app = application
PY
python -m py_compile entry_main.py wsgi.py
git add entry_main.py wsgi.py
git commit -m "chore: switch WSGI to entry_main.app to bust stale cache"
git push
echo
echo "[i] Ahora ve a Render → Settings → Clear build cache → Deploys → Manual Deploy"
