#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="render_entry.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE (render_entry.py). Abortando."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import re, io, sys
p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# 1) Asegurar imports del módulo interactions
if "from backend.modules.interactions import" not in s:
    s += "\nfrom backend.modules.interactions import ensure_schema, register_into, register_alias_into\n"
else:
    s = s.replace(
        "from backend.modules.interactions import ensure_schema",
        "from backend.modules.interactions import ensure_schema, register_into, register_alias_into"
    )

# 2) Inyectar bloque de bootstrap idempotente tras crearse 'app'
TAG = "# >>> interactions_bootstrap"
if TAG not in s:
    boot = f"""
{TAG}
try:
    # Localiza el objeto app si existe
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else (app if 'app' in globals() else None)
except Exception:
    _app = app if 'app' in globals() else None

try:
    if _app is not None:
        with _app.app_context():
            # crear tablas por si falta interaction_event
            try:
                ensure_schema()
            except Exception:
                pass
            # registrar blueprints principales
            try:
                register_into(_app)
            except Exception:
                pass
            # registrar alias /api/ix/...
            try:
                register_alias_into(_app)
            except Exception:
                pass
except Exception:
    # no romper inicio
    pass

# (fin bootstrap)
"""
    # Intento de insertar cerca del final del archivo
    s = s.rstrip() + "\n" + boot

open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py parchado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix: register interactions in render_entry on startup (ensure_schema + blueprints + aliases)" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "[i] Tras el redeploy de Render, verificá:"
cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'
curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .

ID=$(curl -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | jq -r '.[0].id'); echo "Usando ID=$ID"
curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/like"  | sed -n '1,100p'
curl -i -s -X POST "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/view"  | sed -n '1,100p'
curl -i -s      "https://paste12-rmsk.onrender.com/api/ix/notes/$ID/stats"    | sed -n '1,120p'
CMD
