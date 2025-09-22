#!/usr/bin/env bash
set -euo pipefail

echo "== add_db_operationalerror_handler_v1 =="

CANDS=(wsgi.py backend/__init__.py backend/app.py app.py wsgiapp/__init__.py)
target=""
for f in "${CANDS[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -qE 'Flask\(|from flask' "$f"; then target="$f"; break; fi
done
[[ -n "$target" ]] || { echo "ERROR: no encontré módulo Flask para inyectar handler"; exit 1; }

if grep -q 'def __p12_db_operational_error' "$target"; then
  echo "✓ handler ya presente en $target"
  exit 0
fi

cp -f "$target" "$target.bak.$(date +%s)"

python - "$target" <<'PY'
import sys
p=sys.argv[1]
src=open(p,'r',encoding='utf-8').read()
ins = """
# === Paste12 OperationalError handler ===
try:
    from sqlalchemy.exc import OperationalError
    from flask import jsonify
    try:
        from backend.models import db as __p12_db
    except Exception:
        try:
            from models import db as __p12_db
        except Exception:
            __p12_db = None
    @app.errorhandler(OperationalError)
    def __p12_db_operational_error(e):
        try:
            if __p12_db is not None:
                __p12_db.session.remove()
        except Exception:
            pass
        return jsonify(ok=False, error="db_unavailable", kind="OperationalError"), 503
except Exception:
    pass
# === /Paste12 OperationalError handler ===
""".lstrip()
open(p,'w',encoding='utf-8').write(src.rstrip()+"\n\n"+ins)
print("✓ handler inyectado en", p)
PY

echo "OK."
