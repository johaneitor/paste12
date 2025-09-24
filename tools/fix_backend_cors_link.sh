#!/usr/bin/env bash
set -euo pipefail
SHIM="contract_shim.py"

echo "== Fix backend (CORS+Link) via WSGI shim =="

if [[ ! -f "$SHIM" ]]; then
  echo "❌ No existe $SHIM"
  exit 1
fi

MARK="# === P12_SHIM CORS/LINK begin ==="
if grep -q "$MARK" "$SHIM"; then
  echo "→ Shim ya presente (actualizo bloque)"
  sed -i "/$MARK/,/# === P12_SHIM CORS\/LINK end ===/d" "$SHIM"
fi

cat >> "$SHIM" <<'PYCODE'
# === P12_SHIM CORS/LINK begin ===
import json
from typing import List, Tuple

def _p12_wrap_cors_link(app):
    def _app(environ, start_response):
        method = (environ.get('REQUEST_METHOD') or 'GET').upper()
        path   = environ.get('PATH_INFO') or ''

        # Preflight CORS para /api/notes
        if method == 'OPTIONS' and path.startswith('/api/notes'):
            headers = [
                ('Access-Control-Allow-Origin',  '*'),
                ('Access-Control-Allow-Methods', 'GET,POST,OPTIONS'),
                ('Access-Control-Allow-Headers', 'Content-Type'),
                ('Access-Control-Max-Age',       '86400'),
            ]
            start_response('204 No Content', headers)
            return [b'']

        # Interceptar respuesta
        holder = {'status': None, 'headers': None, 'exc': None}
        body_chunks: List[bytes] = []

        def _sr(status: str, headers: List[Tuple[str,str]], exc_info=None):
            holder['status']  = status
            holder['headers'] = list(headers)
            holder['exc']     = exc_info
            # devolvemos un "write" que acumula en body_chunks
            return body_chunks.append

        result = app(environ, _sr)
        try:
            for chunk in result:
                body_chunks.append(chunk)
        finally:
            if hasattr(result, 'close'):
                result.close()

        status  = holder['status'] or '200 OK'
        headers = holder['headers'] or []

        # Asegurar ACAO
        if not any(h[0].lower() == 'access-control-allow-origin' for h in headers):
            headers.append(('Access-Control-Allow-Origin', '*'))

        # Agregar Link: rel=next en GET /api/notes si no existe
        if method == 'GET' and path.startswith('/api/notes'):
            if not any(h[0].lower() == 'link' for h in headers):
                try:
                    raw = b''.join(body_chunks)
                    j = json.loads(raw.decode('utf-8'))
                    items = j if isinstance(j, list) else j.get('items', [])
                    if items:
                        last = items[-1]
                        ts = last.get('timestamp') or last.get('expires_at') or ''
                        nid = last.get('id')
                        if ts and nid is not None:
                            from urllib.parse import quote
                            next_url = f"/api/notes?cursor_ts={quote(str(ts))}&cursor_id={nid}"
                            headers.append(('Link', f'<{next_url}>; rel=\"next\"'))
                except Exception:
                    pass  # no rompemos la respuesta

        # Emitir respuesta
        start_response(status, headers, holder['exc'])
        return body_chunks
    return _app

# Enlazar shim
try:
    application  # type: ignore[name-defined]
except NameError:
    try:
        application = app  # type: ignore[name-defined]
    except NameError:
        raise

application = _p12_wrap_cors_link(application)
# === P12_SHIM CORS/LINK end ===
PYCODE

python - <<'PY'
import py_compile
py_compile.compile("contract_shim.py", doraise=True)
print("✓ py_compile contract_shim.py")
PY

echo "Listo."
