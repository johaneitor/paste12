#!/usr/bin/env bash
set -euo pipefail

echo "== Paste12 backend stabilize v10 (shim Link / X-Next-Cursor) =="

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"

# 1) Escribimos/actualizamos contract_shim.py
cat > contract_shim.py <<'PY'
# -*- coding: utf-8 -*-
"""
Paste12 Contract Shim (v10)
- Inyecta 'Link: <...>; rel="next"' y 'X-Next-Cursor' en GET /api/notes
- Añade 'Access-Control-Expose-Headers: Link, X-Next-Cursor'
- No toca tus rutas; funciona a nivel WSGI.
"""
import json, urllib.parse

HEAD_SHA = ""  # se rellena desde el shell

class _CaptureStart(object):
    __slots__ = ("status","headers","exc_info")
    def __init__(self): self.status="200 OK"; self.headers=[]; self.exc_info=None
    def __call__(self, status, headers, exc_info=None):
        self.status = status; self.headers = list(headers); self.exc_info = exc_info
        # devolvemos un write dummy si nos lo piden
        def _write(_chunk): pass
        return _write

def _get_header(headers, name):
    ln = name.lower()
    for k,v in headers:
        if k.lower()==ln: return v
    return None

def _set_header(headers, name, value):
    ln = name.lower()
    for i,(k,v) in enumerate(headers):
        if k.lower()==ln:
            headers[i] = (k, value); return
    headers.append((name, value))

def _append_header(headers, name, value):
    # no duplica si ya existe exactamente ese valor
    existing = _get_header(headers, name)
    if existing is None:
        headers.append((name, value))
        return
    if value not in existing.split(","):
        _set_header(headers, name, existing + ", " + value)

def _maybe_inject_link(environ, status, headers, body_bytes):
    try:
        # Sólo GET /api/notes con 200 y JSON
        if environ.get("REQUEST_METHOD") != "GET": return headers, body_bytes
        if (environ.get("PATH_INFO") or "") != "/api/notes": return headers, body_bytes
        if not status.startswith("200"): return headers, body_bytes
        ctype = (_get_header(headers, "Content-Type") or "").lower()
        if "application/json" not in ctype: return headers, body_bytes

        data = body_bytes.decode("utf-8")
        payload = json.loads(data)
        items = payload if isinstance(payload, list) else (payload.get("items") if isinstance(payload, dict) else [])
        if not isinstance(items, list) or not items:
            return headers, body_bytes

        # parse limit de la query (si existe)
        qs = environ.get("QUERY_STRING") or ""
        qd = urllib.parse.parse_qs(qs, keep_blank_values=True)
        limit = None
        try:
            if "limit" in qd and qd["limit"] and qd["limit"][0] not in (None,""):
                limit = int(qd["limit"][0])
        except Exception:
            limit = None

        last = items[-1]
        nid = last.get("id")
        ts  = last.get("timestamp") or last.get("ts")
        if nid is None or not ts:
            return headers, body_bytes

        qp = {"cursor_ts": ts, "cursor_id": str(nid)}
        if limit: qp["limit"] = str(limit)
        next_rel = "/api/notes?" + urllib.parse.urlencode(qp)

        # Link y X-Next-Cursor
        if _get_header(headers, "Link") is None:
            headers.append(("Link", f"<{next_rel}>; rel=\"next\""))
        _set_header(headers, "X-Next-Cursor", json.dumps({"cursor_ts": ts, "cursor_id": nid}))

        # Exponer headers al frontend (CORS)
        expose = _get_header(headers, "Access-Control-Expose-Headers") or ""
        expose_list = [h.strip() for h in expose.split(",") if h.strip()]
        for h in ("Link","X-Next-Cursor"):
            if h not in expose_list: expose_list.append(h)
        if expose_list:
            _set_header(headers, "Access-Control-Expose-Headers", ", ".join(expose_list))

    except Exception:
        # silencio: nunca rompemos la respuesta original
        return headers, body_bytes
    return headers, body_bytes

class P12ContractShim:
    def __init__(self, app): self.app = app
    def __call__(self, environ, start_response):
        cap = _CaptureStart()
        app_iter = self.app(environ, cap)
        chunks = []
        try:
            for c in app_iter:
                if c: chunks.append(c)
        finally:
            if hasattr(app_iter, "close"):
                try: app_iter.close()
                except Exception: pass

        body = b"".join(chunks)
        headers, body = _maybe_inject_link(environ, cap.status, cap.headers, body)
        start_response(cap.status, headers, cap.exc_info)
        return [body]

def wrap_app_for_p12(app):
    """ Idempotente: evita doble wrap. """
    if getattr(app, "_p12_wrapped", False):
        return app
    wrapped = P12ContractShim(app)
    setattr(wrapped, "_p12_wrapped", True)
    return wrapped
PY

# Inyectamos SHA en el archivo recién escrito
python - <<PY
from pathlib import Path
p = Path("contract_shim.py")
s = p.read_text(encoding="utf-8")
s = s.replace('HEAD_SHA = ""', 'HEAD_SHA = "%s"' % """${HEAD_SHA}""")
p.write_text(s, encoding="utf-8")
PY

# 2) Asegurar wrap en wsgi.py (idempotente)
if [ -f wsgi.py ]; then
  if ! grep -q "wrap_app_for_p12" wsgi.py; then
    echo "→ parcheando wsgi.py para envolver 'application' con Contract Shim"
    cat >> wsgi.py <<'PY'
# --- Paste12 Contract Shim hook (v10) ---
try:
    from contract_shim import wrap_app_for_p12
    if 'application' in globals():
        application = wrap_app_for_p12(application)
except Exception as _e:
    # nunca romper arranque
    pass
# --- end shim hook ---
PY
  else
    echo "→ wsgi.py ya tenía el hook del shim"
  fi
else
  echo "WARN: wsgi.py no existe en el cwd. Asegúrate de exportar 'application'."
fi

# 3) Compilación rápida
python - <<'PY'
import py_compile
for f in ("contract_shim.py","wsgi.py","wsgiapp/__init__.py"):
    try: py_compile.compile(f, doraise=True)
    except Exception as e: print("py_compile WARN:", f, e)
print("✓ py_compile OK (continuamos)")
PY

echo "Listo. Reinicia el servicio o haz deploy en Render."
