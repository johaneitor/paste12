#!/usr/bin/env bash
set -euo pipefail
SHIM="contract_shim.py"

echo "== Fix backend (POST 201 Created) via shim =="

if [[ ! -f "$SHIM" ]]; then
  echo "❌ No existe $SHIM"
  exit 1
fi

MARK="# === P12_SHIM POST201 begin ==="
if grep -q "$MARK" "$SHIM"; then
  echo "→ Bloque POST201 ya presente (actualizo)"
  sed -i "/$MARK/,/# === P12_SHIM POST201 end ===/d" "$SHIM"
fi

cat >> "$SHIM" <<'PYCODE'
# === P12_SHIM POST201 begin ===
import json

def _p12_wrap_post201(app):
    def _app(environ, start_response):
        method = (environ.get('REQUEST_METHOD') or 'GET').upper()
        path   = environ.get('PATH_INFO') or ''

        holder = {'status': None, 'headers': None, 'exc': None}
        body = []

        def _sr(status, headers, exc_info=None):
            holder['status']  = status
            holder['headers'] = list(headers)
            holder['exc']     = exc_info
            return body.append

        result = app(environ, _sr)
        try:
            for chunk in result:
                body.append(chunk)
        finally:
            if hasattr(result, 'close'):
                result.close()

        status  = holder['status'] or '200 OK'
        headers = holder['headers'] or []

        # Promover 200->201 si POST /api/notes devolvió JSON con id
        if method == 'POST' and path.startswith('/api/notes') and status.startswith('200'):
            try:
                raw = b''.join(body)
                j = json.loads(raw.decode('utf-8'))
                has_id = (isinstance(j, dict) and 'id' in j) or (isinstance(j, list) and j and 'id' in j[0])
                if has_id:
                    status = '201 Created'
                    # (dejamos body intacto)
            except Exception:
                pass

        start_response(status, headers, holder['exc'])
        return body
    return _app

try:
    application  # type: ignore[name-defined]
except NameError:
    try:
        application = app  # type: ignore[name-defined]
    except NameError:
        raise

application = _p12_wrap_post201(application)
# === P12_SHIM POST201 end ===
PYCODE

python - <<'PY'
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
print("✓ py_compile contract_shim.py")
PY

echo "Listo."
