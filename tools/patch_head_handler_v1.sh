#!/usr/bin/env bash
set -euo pipefail

tgt="contract_shim.py"
[[ -f "$tgt" ]] || { echo "ERROR: falta $tgt"; exit 1; }
bak="contract_shim.$(date -u +%Y%m%d-%H%M%SZ).bak"
cp -f "$tgt" "$bak"
echo "[head-shim] Backup: $bak"

python - <<'PY'
import io, re
p="contract_shim.py"
s=io.open(p,"r",encoding="utf-8").read()
orig=s

if "class _HeadDropMiddleware" not in s:
    s += r"""

# == HEAD drop-in middleware (idempotente) ==
class _HeadDropMiddleware:
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        method = environ.get('REQUEST_METHOD','GET').upper()
        if method == 'HEAD':
            # Finge GET para construir headers, descarta cuerpo
            environ['REQUEST_METHOD'] = 'GET'
            body_chunks = []
            def _sr(status, headers, exc_info=None):
                # devolvemos mismo status/headers
                start_response(status, headers, exc_info)
                return lambda x: None
            result = self.app(environ, _sr)
            # Consumimos el iterable sin devolver cuerpo
            try:
                for _ in result:
                    pass
            finally:
                if hasattr(result, 'close'):
                    result.close()
            return []
        return self.app(environ, start_response)
"""

# envolver export "application"
if re.search(r"\napplication\s*=", s):
    s=re.sub(r"(application\s*=\s*.+)", r"_orig_app = \1\napplication = _HeadDropMiddleware(_orig_app)", s, count=1)
elif "application =" not in s and "app =" in s:
    s += "\napplication = _HeadDropMiddleware(app)\n"

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("[head-shim] aplicado OK")
else:
    print("[head-shim] ya estaba OK")
PY

python -m py_compile contract_shim.py && echo "py_compile OK"
