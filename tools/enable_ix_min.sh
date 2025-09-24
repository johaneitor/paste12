#!/usr/bin/env bash
set -euo pipefail
F="render_entry.py"
python - <<'PY'
import io,sys,re
f="render_entry.py"
s=open(f,"r",encoding="utf-8").read()
if "from backend.modules.interactions" in s and "register_alias_into" in s:
    print("[i] Interactions ya parece injertado.")
    sys.exit(0)
inj = """
# --- interactions: registro limpio e idempotente ---
try:
    from backend.modules.interactions import ensure_schema as _ix_ensure_schema
    from backend.modules.interactions import register_into as _ix_register_into
    from backend.modules.interactions import register_alias_into as _ix_register_alias_into
except Exception:
    _ix_ensure_schema = None
    _ix_register_into = None
    _ix_register_alias_into = None

def _ix_bootstrap(_app):
    try:
        if _ix_ensure_schema:
            with _app.app_context():
                _ix_ensure_schema()
        if _ix_register_into:
            _ix_register_into(_app, url_prefix="/api")
        if _ix_register_alias_into:
            _ix_register_alias_into(_app, url_prefix="/api")
    except Exception:
        pass

try:
    _ix_bootstrap(app)
except Exception:
    pass
# --- /interactions ---
"""
# inserta antes de "app.run" o al final
if inj.strip() not in s:
    s = s.rstrip()+"\n\n"+inj
    open(f,"w",encoding="utf-8").write(s)
    print("[ok] injertado bloque de interactions.")
else:
    print("[i] Ya estaba injertado.")
PY
python -m py_compile render_entry.py && echo "[ok] render_entry.py OK"
