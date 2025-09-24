#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
F="render_entry.py"
[ -f "$F" ] || { echo "[!] No existe render_entry.py"; exit 1; }

echo "[+] Backup de $F"
cp -f "$F" "$F.bak.$(date +%s)"

python - "$F" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# 1) Bloque que fuerza registrar SOLO alias + diag del módulo interactions bajo /api/ix y /api/notes/diag
patch = r"""
# >>> force_interactions_alias_only (safe, no endpoint collisions)
try:
    from backend.modules import interactions as _ix
    try:
        # asegurar esquema
        from flask import current_app as _cap
        _app = _cap._get_current_object() if _cap else app
    except Exception:
        try:
            _app = app
        except Exception:
            _app = None
    if _app is not None:
        with _app.app_context():
            try:
                _ix.ensure_schema()
            except Exception:
                pass
        # registrar solo alias (/api/ix/notes/*) y el blueprint principal si faltaran diag/stats
        try:
            _ix.register_alias_into(_app)
        except Exception:
            pass
        # Si no existe /api/notes/diag, intentar registrar el bp principal también
        try:
            has_diag = any(str(r)=="/api/notes/diag" for r in _app.url_map.iter_rules())
        except Exception:
            has_diag = False
        if not has_diag:
            try:
                _ix.register_into(_app)
            except Exception:
                pass
except Exception:
    # silencioso para no romper el startup
    pass
# <<< force_interactions_alias_only
"""

# 2) Inyectar al final si no existe ya
if "force_interactions_alias_only" not in s:
    s = s.rstrip() + "\n" + patch + "\n"

open(p,'w',encoding='utf-8').write(s)
print("[OK] render_entry.py parcheado (alias /api/ix + diag)")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(render_entry): force register interactions alias (/api/ix) + diag safely" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

echo "[i] Tras el redeploy, probá:"
cat <<'CMD'
APP="https://paste12-rmsk.onrender.com"
curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))'
ID="$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id')"; echo "ID=$ID"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
curl -si       "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'
curl -s        "$APP/api/notes/diag" | jq .
CMD
