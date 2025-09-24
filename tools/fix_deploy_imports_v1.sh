#!/usr/bin/env bash
set -euo pipefail
echo "== Fix deploy imports (wsgi ⇄ contract_shim) =="

# 1) wsgi.py robusto: intenta importar 'application' y cae a 'app'; define ambos nombres.
[[ -f wsgi.py ]] && cp -f wsgi.py "wsgi.py.bak.$(date +%s)"
cat > wsgi.py <<'PY'
# Minimal, robust WSGI entry point for Render
# Tries 'application' first, falls back to 'app' from contract_shim.
import os
try:
    from contract_shim import application  # type: ignore
    app = application  # alias
except Exception:
    from contract_shim import app as application  # type: ignore
    app = application

# Optional AdSense injection (if adsense_injector.py is present)
try:
    from adsense_injector import install_adsense_injector  # type: ignore
    install_adsense_injector(application, os.environ.get("ADSENSE_CLIENT","ca-pub-9479870293204581"))
except Exception:
    # In production keep going even if injector isn't available
    pass
PY

python - <<'PY'
import py_compile; py_compile.compile('wsgi.py', doraise=True)
print("✓ py_compile wsgi.py")
PY

# 2) Asegurar export 'application' en contract_shim (alias a app si no existe)
python - <<'PY'
import re, os
p='contract_shim.py'
if not os.path.exists(p):
    print("⚠ contract_shim.py no existe; nada que hacer."); raise SystemExit(0)
s=open(p,'r',encoding='utf-8').read()
if re.search(r'(?m)^\s*application\s*=', s):
    print("→ contract_shim.py ya exporta application"); raise SystemExit(0)
snippet = """
# ---- export alias for gunicorn ----
try:
    application  # type: ignore[name-defined]
except NameError:  # pragma: no cover
    try:
        application = app  # type: ignore[name-defined]
    except NameError:
        pass
"""
open(p,'a',encoding='utf-8').write(snippet)
print("✓ añadido alias application=app en contract_shim.py")
PY

python - <<'PY'
import py_compile; py_compile.compile('contract_shim.py', doraise=True)
print("✓ py_compile contract_shim.py")
PY

echo "Listo. Clear build cache + Deploy en Render."
