#!/usr/bin/env bash
set -euo pipefail

patch_file() {
  local F="$1"
  local TAG="# >>> interactions_module_autoreg"
  [ -f "$F" ] || return 0
  if grep -q "$TAG" "$F"; then
    echo "    - ya parcheado $F"
    return 0
  fi
  echo "    - parcheando $F"
  python - "$F" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()
snippet = r"""
# >>> interactions_module_autoreg
try:
    from flask import current_app as _cap
    _app = _cap._get_current_object() if _cap else app
except Exception:
    try:
        _app = app
    except Exception:
        _app = None

def _has_rule(app, path, method):
    try:
        for r in app.url_map.iter_rules():
            if str(r)==path and method.upper() in r.methods:
                return True
    except Exception:
        pass
    return False

try:
    if _app is not None:
        need_like = not _has_rule(_app, "/api/notes/<int:note_id>/like", "POST")
        need_view = not _has_rule(_app, "/api/notes/<int:note_id>/view", "POST")
        need_stats= not _has_rule(_app, "/api/notes/<int:note_id>/stats","GET")
        if need_like or need_view or need_stats:
            from backend.modules.interactions import interactions_bp
            _app.register_blueprint(interactions_bp, url_prefix="/api")
except Exception as e:
    # silent; no romper inicio de app
    pass
# <<< interactions_module_autoreg
"""
# Inserta al final del archivo
s = s.rstrip() + "\n" + snippet
open(p,'w',encoding='utf-8').write(s)
print("[OK] parcheado", p)
PY
}

echo "[+] Buscando entrypoints para parchear…"
patched=0
for f in wsgi.py run.py render_entry.py; do
  if [ -f "$f" ]; then
    patch_file "$f"; patched=1
  fi
done
if [ $patched -eq 0 ]; then
  echo "[!] No encontré wsgi.py/run.py/render_entry.py. Crea uno de esos para registrar el módulo."
fi
