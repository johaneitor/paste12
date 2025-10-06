#!/usr/bin/env bash
set -euo pipefail

PY_INIT="wsgiapp/__init__.py"
PATCH_MOD="wsgiapp/p12_patch.py"

mkdir -p wsgiapp

cat > "$PATCH_MOD" <<'PY'
# -*- coding: utf-8 -*-
import os, time, hashlib, json
from flask import request, Response

REPORT_THRESHOLD = int(os.getenv("P12_REPORT_DELETE_THRESHOLD","3"))
RATE_MS          = int(os.getenv("P12_RATE_MIN_INTERVAL_MS","400"))
LIST_LIMIT_MAX   = int(os.getenv("P12_LIST_LIMIT_MAX","50"))
LIST_LIMIT_DEF   = int(os.getenv("P12_LIST_LIMIT_DEFAULT","10"))

_last_hit = {}

def _now_ms():
    return int(time.time() * 1000)

def _ip(req):
    xf = (req.headers.get('X-Forwarded-For') or '').split(',')[0].strip()
    return xf or (req.remote_addr or '0.0.0.0')

def _fp(req):
    s = (_ip(req) or '') + '|' + (req.headers.get('User-Agent') or '')
    return hashlib.sha1(s.encode('utf-8')).hexdigest()

def _rate_ok(key):
    t = _now_ms(); last = _last_hit.get(key, 0)
    if t - last < RATE_MS:
        return False
    _last_hit[key] = t
    return True

def _db():
    # conexión directa a Postgres (Render expone DATABASE_URL)
    try:
        import psycopg2
    except Exception:
        return None
    url = os.environ.get('DATABASE_URL')
    if not url:
        return None
    if 'sslmode=' not in url:
        url = url + ('&' if '?' in url else '?') + 'sslmode=require'
    return psycopg2.connect(url)

def _ensure_tables():
    conn = _db()
    if not conn:
        return
    try:
        with conn, conn.cursor() as cur:
            cur.execute("""
            CREATE TABLE IF NOT EXISTS note_reports(
                note_id BIGINT NOT NULL,
                fp      TEXT   NOT NULL,
                ts      TIMESTAMPTZ DEFAULT NOW(),
                PRIMARY KEY(note_id, fp)
            );
            """)
            # columnas de conteo por si faltaran (no falla si existen)
            for col in ("views","likes","reports"):
                try:
                    cur.execute(f"ALTER TABLE notes ADD COLUMN IF NOT EXISTS {col} INTEGER DEFAULT 0;")
                except Exception:
                    pass
    finally:
        conn.close()

TERMS_HTML = """<!doctype html><meta charset="utf-8"><title>Términos</title>
<body data-single="1">
<h1>Términos de uso</h1>
<p>Servicio experimental. No publiques datos sensibles. Los contenidos pueden moderarse ante abuso.</p>
</body>"""

PRIVACY_HTML = """<!doctype html><meta charset="utf-8"><title>Privacidad</title>
<body data-single="1">
<h1>Política de privacidad</h1>
<p>Sin tracking personalizado. Se registran metadatos técnicos para operar y proteger la plataforma.</p>
</body>"""

def apply_p12_patch(app):
    # Asegurar tablas auxiliares (idempotente)
    try:
        _ensure_tables()
    except Exception as e:
        print("p12_patch ensure tables:", e)

    @app.before_request
    def _p12_intercept():
        p = request.path
        m = request.method.upper()

        # Fallbacks no vacíos para /terms y /privacy
        if p in ("/terms", "/privacy") and m == "GET":
            html = TERMS_HTML if p == "/terms" else PRIVACY_HTML
            return Response(html, 200, [("Content-Type","text/html; charset=utf-8"),
                                        ("Cache-Control","no-store")])

        # Anti-abuso en listados: clamp de ?limit=
        if p.startswith("/api/notes") and m == "GET":
            lim = request.args.get("limit")
            if lim:
                try:
                    n = int(lim)
                    if n < 1 or n > LIST_LIMIT_MAX:
                        body = json.dumps({"error":"bad_limit","max":LIST_LIMIT_MAX})
                        return Response(body, 400, [("Content-Type","application/json")])
                except Exception:
                    return Response(json.dumps({"error":"bad_limit"}), 400, [("Content-Type","application/json")])

        # Rate limit primitivo por IP en endpoints sensibles
        if p in ("/api/like","/api/view","/api/report","/api/notes") and m in ("GET","POST"):
            key = p + ":" + _ip(request)
            if not _rate_ok(key):
                return Response(json.dumps({"error":"too_many_requests"}),
                                429, [("Content-Type","application/json"),("Retry-After","1")])

        # VIEW: asegurar conteo visible y 404 limpio
        if p == "/api/view" and m in ("GET","POST"):
            nid = request.args.get("id") if m=="GET" else ((request.json or {}).get("id") if request.is_json else request.form.get("id"))
            try:
                nid = int(nid)
            except Exception:
                return Response(json.dumps({"error":"bad_id"}), 400, [("Content-Type","application/json")])
            conn = _db()
            if not conn:
                return None  # deja que la app original responda
            try:
                with conn, conn.cursor() as cur:
                    cur.execute("UPDATE notes SET views = COALESCE(views,0)+1 WHERE id=%s RETURNING id, views", (nid,))
                    row = cur.fetchone()
                    if not row:
                        return Response(json.dumps({"error":"not_found"}), 404, [("Content-Type","application/json")])
                    body = json.dumps({"ok":True,"id":row[0],"views":row[1]})
                    return Response(body, 200, [("Content-Type","application/json"),("Cache-Control","no-store")])
            finally:
                conn.close()

        # LIKE: asegurar 404 limpio
        if p == "/api/like" and m in ("GET","POST"):
            nid = request.args.get("id") if m=="GET" else ((request.json or {}).get("id") if request.is_json else request.form.get("id"))
            try:
                nid = int(nid)
            except Exception:
                return Response(json.dumps({"error":"bad_id"}), 400, [("Content-Type","application/json")])
            conn = _db()
            if not conn:
                return None
            try:
                with conn, conn.cursor() as cur:
                    cur.execute("UPDATE notes SET likes = COALESCE(likes,0)+1 WHERE id=%s RETURNING id, likes", (nid,))
                    row = cur.fetchone()
                    if not row:
                        return Response(json.dumps({"error":"not_found"}), 404, [("Content-Type","application/json")])
                    body = json.dumps({"ok":True,"id":row[0],"likes":row[1]})
                    return Response(body, 200, [("Content-Type","application/json"),("Cache-Control","no-store")])
            finally:
                conn.close()

        # REPORT: requiere 3 reportes de personas distintas para borrar
        if p == "/api/report" and m in ("GET","POST"):
            nid = request.args.get("id") if m=="GET" else ((request.json or {}).get("id") if request.is_json else request.form.get("id"))
            try:
                nid = int(nid)
            except Exception:
                return Response(json.dumps({"error":"bad_id"}), 400, [("Content-Type","application/json")])
            fp = _fp(request)
            conn = _db()
            if not conn:
                return None
            try:
                with conn, conn.cursor() as cur:
                    # registrar reportero único
                    cur.execute("INSERT INTO note_reports(note_id, fp) VALUES (%s,%s) ON CONFLICT DO NOTHING", (nid, fp))
                    # subir contador visible
                    cur.execute("UPDATE notes SET reports = COALESCE(reports,0)+1 WHERE id=%s RETURNING id, reports", (nid,))
                    row = cur.fetchone()
                    if not row:
                        return Response(json.dumps({"error":"not_found"}), 404, [("Content-Type","application/json")])
                    # cuántos reporteros únicos
                    cur.execute("SELECT COUNT(*) FROM note_reports WHERE note_id=%s", (nid,))
                    distinct = cur.fetchone()[0]
                    if distinct >= REPORT_THRESHOLD:
                        # borrar nota
                        cur.execute("DELETE FROM notes WHERE id=%s RETURNING id", (nid,))
                        deleted = cur.fetchone()
                        if deleted:
                            body = json.dumps({"ok":True,"id":nid,"action":"deleted","reports":row[1],"distinct_reporters":distinct})
                            return Response(body, 200, [("Content-Type","application/json"),("Cache-Control","no-store")])
                    body = json.dumps({"ok":True,"id":row[0],"reports":row[1],"distinct_reporters":distinct,"action":"flagged"})
                    return Response(body, 200, [("Content-Type","application/json"),("Cache-Control","no-store")])
            finally:
                conn.close()

        return None  # continuar con la app base
PY

# Inyectar llamada apply_p12_patch(application) al final de __init__.py (idempotente)
python - <<'PY'
import io, re, py_compile, sys
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()
if "apply_p12_patch(" not in s:
    s += "\n# p12: parche drop-in (términos, vistas, reportes 3x, anti-abuso)\n"
    s += "try:\n"
    s += "    from .p12_patch import apply_p12_patch\n"
    s += "    apply_p12_patch(application)\n"
    s += "except Exception as _e:\n"
    s += "    print('p12_patch skip:', _e)\n"
    io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
py_compile.compile("wsgiapp/p12_patch.py", doraise=True)
print("PATCH_OK", p, "and", "wsgiapp/p12_patch.py")
PY

echo "OK: wsgiapp/__init__.py compilado"
