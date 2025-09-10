
from sqlalchemy import text as _text

def _json(code, payload):
    """(status, headers, body) JSON estándar, no-store, idempotente"""
    body = _json_mod.dumps(payload, default=str).encode("utf-8")
    status = f"{code} OK"
    headers = [
        ("Content-Type", "application/json; charset=utf-8"),
        ("Content-Length", str(len(body))),
        ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
        ("X-WSGI-Bridge", "1"),
    ]
    return status, headers, body



T = _text
import os, sys, json, mimetypes, hashlib
from importlib import import_module
from typing import Callable, Tuple
from datetime import datetime, timedelta, timezone

_THIS = os.path.abspath(__file__)
_REPO_DIR = os.path.dirname(os.path.dirname(_THIS))
if _REPO_DIR not in sys.path:
    sys.path.insert(0, _REPO_DIR)

CANDIDATES = ["app:app", "run:app", "render_entry:app", "entry_main:app"]

def _resolve_app():
    last_err = None
    for spec in CANDIDATES:
        try:
            os.environ["APP_MODULE"] = spec
            sys.modules.pop("patched_app", None)
            pa = import_module("patched_app")
            return getattr(pa, "app")
        except Exception as e:
            last_err = e
    print(f"[wsgiapp] WARNING: no pude resolver APP_MODULE (probados {CANDIDATES}). Último error: {last_err!r}")
    return None

def _bootstrap_db():
    from sqlalchemy import create_engine, text
    url = os.environ.get("DATABASE_URL", "") or os.environ.get("SQLALCHEMY_DATABASE_URI","")
    if not url:
        return
    eng = create_engine(url, pool_pre_ping=True)
    with eng.begin() as cx:
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS note(
                id SERIAL PRIMARY KEY,
                title TEXT, url TEXT, summary TEXT, content TEXT,
                text TEXT,
                timestamp TIMESTAMPTZ DEFAULT NOW(),
                expires_at TIMESTAMPTZ,
                likes INT DEFAULT 0,
                views INT DEFAULT 0,
                reports INT DEFAULT 0,
                author_fp VARCHAR(64)
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS report_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        cx.execute(text("""
            CREATE TABLE IF NOT EXISTS like_log(
                id SERIAL PRIMARY KEY,
                note_id INT NOT NULL,
                fingerprint VARCHAR(128) NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """))
        # índices (pueden ya existir)
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_report_note_fp ON report_log (note_id, fingerprint)"))
        except Exception: pass
        try: cx.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp ON like_log (note_id, fingerprint)"))
        except Exception: pass
_bootstrap_db()

def _json(status: int, data: dict) -> Tuple[str, list, bytes]:
    body = json.dumps(data, default=str).encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", "application/json; charset=utf-8"),
               ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _html(status: int, body_html: str, ctype="text/html; charset=utf-8"):
    body = body_html.encode("utf-8")
    status_line = f"{status} " + ("OK" if status == 200 else "ERROR")
    headers = [("Content-Type", ctype), ("Content-Length", str(len(body)))]
    return status_line, headers, body

def _finish(start_response, status, headers, body, method, extra_headers=None):
    headers = list(headers)
    if extra_headers:
        headers += extra_headers
    headers.append(("X-WSGI-Bridge", "1"))
    if method == "HEAD":
        headers = [(k, ("0" if k.lower()=="content-length" else v)) for k,v in headers]
        start_response(status, headers)
        return [b""]
    start_response(status, headers)
    return [body]

def _engine():
    from sqlalchemy import create_engine
    url = os.environ.get("SQLALCHEMY_DATABASE_URI") or os.environ.get("DATABASE_URL")
    if not url:
        raise RuntimeError("DATABASE_URL/SQLALCHEMY_DATABASE_URI no definido")
    return create_engine(url, pool_pre_ping=True)

def _fingerprint(environ) -> str:
    fp = environ.get("HTTP_X_FP")
    if fp: return fp[:128]
    ip = (environ.get("HTTP_X_FORWARDED_FOR","").split(",")[0].strip() or
          environ.get("REMOTE_ADDR","") or "0.0.0.0")
    ua = environ.get("HTTP_USER_AGENT","")
    return hashlib.sha1(f"{ip}|{ua}".encode("utf-8")).hexdigest()

def _columns(conn) -> set:
    from sqlalchemy import text as _text
    dialect = conn.engine.dialect.name
    if dialect.startswith("sqlite"):
        rows = conn.execute(_text("PRAGMA table_info(note)")).mappings().all()
        return {r["name"] for r in rows}
    else:
        q = _text("""
            SELECT column_name
            FROM information_schema.columns
            WHERE table_name = 'note' AND table_schema = current_schema()
        """)
        rows = conn.execute(q).mappings().all()
        return {r["column_name"] for r in rows}

def _build_select(cols: set, with_where: bool) -> str:
    base = ["id", "timestamp", "likes", "views", "reports", "author_fp"]
    textish = ["text", "expires_at"]
    article = ["title", "url", "summary", "content"]
    parts = []
    for c in base + textish + article:
        parts.append(c if c in cols else f"NULL AS {c}")
    where = "WHERE (timestamp < :ts) OR (timestamp = :ts AND id < :id)" if with_where else ""
    return f"SELECT {', '.join(parts)} FROM note {where} ORDER BY timestamp DESC, id DESC LIMIT :lim"

def _normalize_row(r: dict) -> dict:
    keys = ["id","text","title","url","summary","content","timestamp","expires_at","likes","views","reports","author_fp"]
    out = {k: r.get(k) for k in keys}
    if not out.get("text"):
        out["text"] = out.get("content") or out.get("summary")
    return out

def _notes_query(qs: str):
    from urllib.parse import parse_qs
    from sqlalchemy import text as _text
    try:
        params = parse_qs(qs or "", keep_blank_values=True)
        def _get(name, cast=lambda x:x, default=None):
            v = params.get(name, [None])[0]
            return default if v is None or v=="" else cast(v)
        limit     = max(1, min(_get("limit", int, 20), 100))
        cursor_ts = _get("cursor_ts", str, None)
        cursor_id = _get("cursor_id", int, None)
        with _engine().begin() as cx:
            cols = _columns(cx)
            sql = _build_select(cols, with_where=bool(cursor_ts and cursor_id))
            args = {"lim": limit}
            if cursor_ts and cursor_id:
                args.update({"ts": cursor_ts, "id": cursor_id})
            rows = cx.execute(_text(sql), args).mappings().all()
        items = [_normalize_row(dict(r)) for r in rows]
        next_cursor = None
        if items:
            last = items[-1]
            if last.get("timestamp") is not None and last.get("id") is not None:
                next_cursor = {"cursor_ts": str(last["timestamp"]), "cursor_id": last["id"]}
        return 200, {"ok": True, "items": items, "next": next_cursor}, next_cursor
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}, None

def _insert_note(payload: dict):
    from sqlalchemy import text as _text
    text_val = (payload.get("text") or "").strip()
    if not text_val:
        return 400, {"ok": False, "error": "text_required"}
    ttl_hours = int(payload.get("ttl_hours") or os.environ.get("NOTE_TTL_HOURS", "12") or "12")
    now = datetime.now(timezone.utc)
    exp = now + timedelta(hours=ttl_hours)
    try:
        with _engine().begin() as cx:
            cols = _columns(cx)
            body_col = "text" if "text" in cols else ("content" if "content" in cols else ("summary" if "summary" in cols else None))
            if body_col is None:
                return 500, {"ok": False, "error": "no_textual_column"}
            fields, marks, args = [body_col], [":body"], {"body": text_val}
            if "timestamp" in cols:
                fields.append("timestamp"); marks.append(":ts"); args["ts"] = now
            if "expires_at" in cols:
                fields.append("expires_at"); marks.append(":exp"); args["exp"] = exp
            if "author_fp" in cols and payload.get("author_fp"):
                fields.append("author_fp"); marks.append(":fp"); args["fp"] = payload.get("author_fp")
            sql = f"INSERT INTO note({', '.join(fields)}) VALUES ({', '.join(marks)})"
            id_val = None
            try:
                row = cx.execute(_text(sql + " RETURNING id"), args).first()
                if row: id_val = row[0]
            except Exception:
                cx.execute(_text(sql), args)
                try:
                    id_val = cx.execute(_text("SELECT lastval()")).scalar()
                except Exception:
                    id_val = cx.execute(_text("SELECT MAX(id) FROM note")).scalar()
            cols2 = _columns(cx)
            sel = _build_select(cols2, with_where=False) + " OFFSET 0"
            row = cx.execute(_text(f"SELECT * FROM ({sel}) x WHERE id=:id"), {"id": id_val, "lim": 1}).mappings().first()
            item = _normalize_row(dict(row)) if row else {"id": id_val, "text": text_val, "likes": 0, "views": 0, "reports": 0}
        return 201, {"ok": True, "item": item}
    except Exception as e:
        return 500, {"ok": False, "error": str(e)}

def _inc_simple(note_id: int, column: str):
    from sqlalchemy import text as _text
    with _engine().begin() as cx:
        cx.execute(_text(f"UPDATE note SET {column}=COALESCE({column},0)+1 WHERE id=:id"), {"id": note_id})
        row = cx.execute(_text("SELECT id, likes, views, reports FROM note WHERE id=:id"), {"id": note_id}).mappings().first()
        if not row:
            return 404, {"ok": False, "error": "not_found"}
        d = dict(row); d["ok"] = True
        return 200, d

def _report_once(note_id: int, fp: str, threshold: int):
    """Dedupe por fingerprint y borra al alcanzar el umbral. Orden seguro de borrado (logs -> nota)."""
    from sqlalchemy import text as _text
    with _engine().begin() as cx:
        # 1) ¿ya reportó esta persona?
        exists = cx.execute(_text(
            "SELECT 1 FROM report_log WHERE note_id=:id AND fingerprint=:fp LIMIT 1"
        ), {"id": note_id, "fp": fp}).scalar()
        if not exists:
            cx.execute(_text(
                "INSERT INTO report_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())"
            ), {"id": note_id, "fp": fp})

        # 2) Sincronizar contador
        count = int(cx.execute(_text(
            "SELECT COUNT(*) FROM report_log WHERE note_id=:id"
        ), {"id": note_id}).scalar() or 0)
        cx.execute(_text("UPDATE note SET reports=:c WHERE id=:id"), {"id": note_id, "c": count})

        # 3) Umbral alcanzado → borrar primero logs (evita FK), luego la nota
        if count >= threshold:
            try:
                cx.execute(_text("DELETE FROM report_log WHERE note_id=:id"), {"id": note_id})
                try:
                    cx.execute(_text("DELETE FROM like_log WHERE note_id=:id"), {"id": note_id})
                except Exception:
                    pass
                cx.execute(_text("DELETE FROM note WHERE id=:id"), {"id": note_id})
            except Exception as e:
                return 500, {"ok": False, "error": f"remove_failed: {e}"}
            return 200, {"ok": True, "id": note_id, "likes": 0, "views": 0, "reports": count, "removed": True}

        # 4) Caso normal
        row = cx.execute(_text(
            "SELECT id, likes, views, reports FROM note WHERE id=:id"
        ), {"id": note_id}).mappings().first()
        if not row:
            return 404, {"ok": False, "error": "not_found"}
        d = dict(row); d["ok"] = True; d["removed"] = False
        return 200, d
def _try_read(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except Exception:
        return None

def _serve_index_html():
    override = os.environ.get("WSGI_BRIDGE_INDEX")
    if override:
        candidates = [override]
    else:
        candidates = [
            os.path.join(_REPO_DIR, "backend", "static", "index.html"),
            os.path.join(_REPO_DIR, "public", "index.html"),
            os.path.join(_REPO_DIR, "frontend", "index.html"),
            os.path.join(_REPO_DIR, "index.html"),
        ]
    for p in candidates:
        if p and os.path.isfile(p):
            body = _try_read(p)
            if body is not None:
                ctype = mimetypes.guess_type(p)[0] or "text/html"
                status, headers, body = _html(200, body.decode("utf-8", "ignore"), f"{ctype}; charset=utf-8")
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                headers += [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                            ("X-Index-Source", "bridge")]
                return status, headers, body
    html = """<!doctype html>
<html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1>
<p>Backend vivo (bridge fallback). Endpoints:</p>
<ul>
  <li><a href="/api/notes">/api/notes</a></li>
  <li><a href="/api/notes_fallback">/api/notes_fallback</a></li>
  <li><a href="/api/notes_diag">/api/notes_diag</a></li>
  <li><a href="/api/deploy-stamp">/api/deploy-stamp</a></li>
</ul>
</body></html>"""
    status, headers, body = _html(200, html)
    headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
    headers += [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge")]
    return status, headers, body

_TERMS_HTML = """<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Términos</title>
<style>body{font-family:system-ui;margin:24px;line-height:1.55;max-width:860px}
h1{background:linear-gradient(90deg,#8fd3d0,#ffb38a,#f9a3c7);-webkit-background-clip:text;color:transparent}</style></head>
<body><h1>Términos y Condiciones</h1>
<p>Este servicio se ofrece “tal cual”. No garantizamos disponibilidad ni integridad del contenido publicado.</p>
<p>Contenido inapropiado o ilegal podrá ser removido. No uses el servicio para spam ni para infringir derechos.</p>
<p>Al usarlo, aceptás estos términos.</p>
</body></html>"""

_PRIVACY_HTML = """<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Privacidad</title>
<style>body{font-family:system-ui;margin:24px;line-height:1.55;max-width:860px}
h1{background:linear-gradient(90deg,#8fd3d0,#ffb38a,#f9a3c7);-webkit-background-clip:text;color:transparent}</style></head>
<body><h1>Política de Privacidad</h1>
<p>Guardamos datos mínimos para operar (p. ej., texto de notas y métricas agregadas).</p>
<p>Para limitar reportes repetidos generamos una <em>huella</em> técnica basada en IP y User-Agent; no es identificación personal.</p>
<p>Podemos almacenar <code>cookies/localStorage</code> para mejorar la experiencia. No vendemos tu información.</p>
</body></html>"""

def _middleware(inner_app: Callable | None, is_fallback: bool) -> Callable:
    def _app(environ, start_response):
        path   = environ.get("PATH_INFO", "")
        method = environ.get("REQUEST_METHOD", "GET").upper()
        qs     = environ.get("QUERY_STRING", "")

        # Preflight CORS/OPTIONS para /api/*

        if path in ("/", "/index.html") and method in ("GET","HEAD"):
            if inner_app is None or os.environ.get("FORCE_BRIDGE_INDEX") == "1":
                status, headers, body = _serve_index_html()
                return _finish(start_response, status, headers, body, method)

        if path == "/terms" and method in ("GET","HEAD"):
            status, headers, body = _html(200, _TERMS_HTML)
            return _finish(start_response, status, headers, body, method)
        if path == "/privacy" and method in ("GET","HEAD"):
            status, headers, body = _html(200, _PRIVACY_HTML)
            return _finish(start_response, status, headers, body, method)

        if path == "/api/health" and method in ("GET","HEAD"):
            status, headers, body = _json(200, {"ok": True})
            return _finish(start_response, status, headers, body, method)
        # Preflight CORS/OPTIONS para /api/*
        if method == "OPTIONS" and path.startswith("/api/"):
            origin = environ.get("HTTP_ORIGIN")
            hdrs = [
                ("Content-Type", "application/json; charset=utf-8"),
                ("Access-Control-Allow-Methods", "GET,POST,OPTIONS"),
                ("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization"),
                ("Access-Control-Max-Age", "86400"),
            ]
            if origin:
                hdrs += [
                    ("Access-Control-Allow-Origin", origin),
                    ("Vary", "Origin"),
                    ("Access-Control-Allow-Credentials", "true"),
                    ("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit"),
                ]
            req_hdrs = environ.get("HTTP_ACCESS_CONTROL_REQUEST_HEADERS")
            if req_hdrs:
                hdrs = [(k,v) for (k,v) in hdrs if k.lower() != "access-control-allow-headers"] + [("Access-Control-Allow-Headers", req_hdrs)]
            start_response("204 No Content", hdrs)
            return [b""]


        if path == "/api/deploy-stamp" and method in ("GET","HEAD"):
            try:
                import os, json, datetime as _dt  # local, robusto
                import os, json  # local, por robustez en runtime
                commit = (os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "")
                date   = (os.environ.get("DEPLOY_STAMP") or os.environ.get("RENDER_DEPLOY") or "")
                if not date:
                    date = _dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z"
                # Respuesta compatible: {deploy:{commit,date}} y también {commit,date}
                payload = {"ok": True, "deploy": {"commit": commit, "date": date}, "commit": commit, "date": date}
                status, headers, body = _json(200, payload)
            except Exception as e:
                status, headers, body = _json(500, {"ok": False, "error": f"deploy_stamp: {e}"})
            return _finish(start_response, status, headers, body, method)

        if path in ("/api/notes", "/api/notes_fallback") and method in ("GET","HEAD"):
            try:
                # Camino normal
                code, payload, nxt = _notes_query(qs)  # type: ignore[name-defined]
            except Exception as e:
                # Fallback SQL simple para no romper el frontend si falla _notes_query
                try:
                    from sqlalchemy import text as _text
                    from urllib.parse import parse_qs as _parse_qs
                    _q = _parse_qs(qs or "", keep_blank_values=True)
                    try:
                        lim = int((_q.get("limit", [20]) or [20])[0] or 20)
                    except Exception:
                        lim = 20
                    if lim < 1: lim = 1
                    if lim > 100: lim = 100
                    with _engine().begin() as cx:  # type: ignore[name-defined]
                        rows = cx.execute(_text(
                            "SELECT id, text, title, url, summary, content, timestamp, expires_at, likes, views, reports, author_fp "
                            "FROM note ORDER BY timestamp DESC, id DESC LIMIT :lim"
                        ), {"lim": lim}).mappings().all()
                    items = [ _normalize_row(dict(r)) for r in rows ]  # type: ignore[name-defined]
                    code, payload, nxt = 200, {"ok": True, "items": items}, None
                except Exception as e2:
                    code, payload, nxt = 500, {"ok": False, "error": f"notes_query_failed: {e}; fallback_failed: {e2}"}, None
            status, headers, body = _json(code, payload)  # type: ignore[name-defined]
            extra = []
            try:
                if nxt and nxt.get("cursor_ts") and nxt.get("cursor_id"):
                    from urllib.parse import quote
                    ts_q = quote(str(nxt["cursor_ts"]), safe="")
                    link = f'</api/notes?cursor_ts={ts_q}&cursor_id={nxt["cursor_id"]}>; rel="next"'
                    extra.append(("Link", link))
                    extra.append(("X-Next-Cursor", json.dumps(nxt)))
            except Exception:
                pass
            return _finish(start_response, status, headers, body, method, extra_headers=extra)  # type: ignore[name-defined]
        if path == "/api/notes" and method == "POST":
            try:
                ctype = environ.get("CONTENT_TYPE","")
                length = int(environ.get("CONTENT_LENGTH","0") or "0")
                raw = environ["wsgi.input"].read(length) if length > 0 else b""
                data = {}
                if "application/json" in ctype:
                    try: data = json.loads(raw.decode("utf-8") or "{}")
                    except Exception: data = {}
                else:
                    from urllib.parse import parse_qs
                    qd = parse_qs(raw.decode("utf-8"), keep_blank_values=True)
                    data = {k: v[0] for k,v in qd.items()}
                code, payload = _insert_note(data)
            except Exception as e:
                code, payload = 500, {"ok": False, "error": str(e)}
            status, headers, body = _json(code, payload)
            return _finish(start_response, status, headers, body, method)

        if path.startswith("/api/notes/") and method == "POST":
            tail = path.removeprefix("/api/notes/")
            try:
                sid, action = tail.split("/", 1)
                note_id = int(sid)
            except Exception:
                note_id = None
                action = ""
            if note_id:
                if action == "like":
                    try:
                        from sqlalchemy import text as _text
                        with _engine().begin() as cx:  # type: ignore[name-defined]
                            # DDL idempotente (tabla e índice)
                            cx.execute(_text("""CREATE TABLE IF NOT EXISTS like_log(
                                note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                                fingerprint VARCHAR(128) NOT NULL,
                                created_at TIMESTAMPTZ DEFAULT NOW(),
                                PRIMARY KEY (note_id, fingerprint)
                            )"""))
                            cx.execute(_text("""CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                                ON like_log(note_id, fingerprint)"""))
                            # Inserción deduplicada
                            fp = _fingerprint(environ)  # type: ignore[name-defined]
                            inserted = False
                            try:
                                cx.execute(_text(
                                    "INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())"
                                ), {"id": note_id, "fp": fp})
                                inserted = True
                            except Exception:
                                inserted = False
                            if inserted:
                                cx.execute(_text(
                                    "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                                ), {"id": note_id})
                            row = cx.execute(_text(
                                "SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id"
                            ), {"id": note_id}).first()
                            likes   = int(row[0] or 0)
                            views   = int(row[1] or 0)
                            reports = int(row[2] or 0)
                        code, payload = 200, {"ok": True, "id": note_id, "likes": likes, "views": views, "reports": reports, "deduped": (not inserted)}
                    except Exception as e:
                        code, payload = 500, {"ok": False, "error": f"like_failed: {e}" }
                elif action == "view":
                    code, payload = _inc_simple(note_id, "views")  # type: ignore[name-defined]
                elif action == "report":
                    try:
                        import os
                        threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")
                    except Exception:
                        threshold = 5
                    fp = _fingerprint(environ)  # type: ignore[name-defined]
                    try:
                        code, payload = _report_once(note_id, fp, threshold)  # type: ignore[name-defined]
                    except Exception as e:
                        code, payload = 500, {"ok": False, "error": f"report_failed: {e}" }
                else:
                    code, payload = 404, {"ok": False, "error": "unknown_action"}
                status, headers, body = _json(code, payload)  # type: ignore[name-defined]
                return _finish(start_response, status, headers, body, method)  # type: ignore[name-defined]
        if path.startswith("/api/notes/") and method == "GET":
            tail = path.removeprefix("/api/notes/")
            try:
                note_id = int(tail)
            except Exception:
                note_id = None
            if note_id:
                from sqlalchemy import text as _text
                with _engine().begin() as cx:  # type: ignore[name-defined]
                    cols = _columns(cx)  # type: ignore[name-defined]
                    sel = _build_select(cols, with_where=False) + " OFFSET 0"  # type: ignore[name-defined]
                    row = cx.execute(_text(f"SELECT * FROM ({sel}) x WHERE id=:id"), {"id": note_id, "lim": 1}).mappings().first()
                if not row:
                    status, headers, body = _json(404, {"ok": False, "error": "not_found"})  # type: ignore[name-defined]
                else:
                    status, headers, body = _json(200, {"ok": True, "item": _normalize_row(dict(row))})  # type: ignore[name-defined]
                return _finish(start_response, status, headers, body, method)  # type: ignore[name-defined]

    return _app
def _compose_with_ext(app):
    """
    Monta apps externas bajo prefijos, a partir de EXT_APPS.
    Formatos aceptados (separar múltiples por comas):
      - "mipkg.mod:app@/ext/foo"
      - "mipkg.mod:create_app@/ext/bar"  (si callable, se invoca sin args)
    """
    import os, importlib
    spec = (os.environ.get("EXT_APPS") or "").strip()
    if not spec:
        return app
    mounts = []
    for raw in [s.strip() for s in spec.split(",") if s.strip()]:
        if "@/" not in raw:  # validación mínima
            continue
        left, prefix = raw.split("@", 1)
        mod, _, attr = left.partition(":")
        try:
            m = importlib.import_module(mod)
            target = getattr(m, attr or "app", None)
            if callable(target):
                try:
                    # si es factoría devuelve la app; si es ya una app, dejar tal cual
                    import inspect
                    if inspect.signature(target).parameters:
                        ext = target  # requiere args → asumimos ya es WSGI
                    else:
                        maybe = target()
                        ext = maybe if callable(maybe) else target
                except Exception:
                    ext = target
            else:
                raise RuntimeError("objeto no callable")
            mounts.append((prefix, ext))
        except Exception:
            # ignorar entradas inválidas
            pass

    if not mounts:
        return app

    def _router(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        for pref, ext in mounts:
            if path.startswith(pref):
                return ext(environ, start_response)
        return app(environ, start_response)
    return _router

# --- WSGI entrypoint (nivel módulo) ---
try:
    _app = _resolve_app()  # type: ignore[name-defined]
except Exception:
    _app = None  # fallback

def _root_force_mw(inner):
    # Envuelve la app para inyectar CORS en TODAS las respuestas cuando hay Origin
    def _mw(environ, start_response):
        origin = environ.get("HTTP_ORIGIN")
        # interceptamos la respuesta para poder ajustar headers
        status_holder = {"status": "200 OK"}
        headers_holder = {"headers": []}
        def sr(status, headers, exc_info=None):
            status_holder["status"] = status
            headers_holder["headers"] = list(headers)
            # wsgi exige devolver un write(); pero no lo usamos
            return (lambda data: None)
        body_iter = inner(environ, sr)
        body = b"".join(body_iter) if hasattr(body_iter, "__iter__") else (body_iter or b"")
        headers = headers_holder["headers"]

        # remueve Content-Length para no romper si cambiamos headers
        headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]

        if origin:
            # upsert helpers
            low = {k.lower(): i for i, (k, _) in enumerate(headers)}
            def upsert(k, v):
                i = low.get(k.lower())
                if i is None:
                    headers.append((k, v))
                    low[k.lower()] = len(headers) - 1
                else:
                    k0, _ = headers[i]; headers[i] = (k0, v)
            upsert("Access-Control-Allow-Origin", origin)  # eco del origin
            upsert("Vary", "Origin")
            upsert("Access-Control-Allow-Credentials", "true")
            upsert("Access-Control-Expose-Headers", "Link, X-Next-Cursor, X-Summary-Applied, X-Summary-Limit")

        start_response(status_holder["status"], headers)
        return [body]
    return _mw
app  = _middleware(_app, is_fallback=(_app is None))  # type: ignore[name-defined]

# Aplica _root_force_mw si existe (CORS/OPTIONS y otros hooks)
try:
    _root_force_mw  # noqa: F821
except NameError:
    pass
else:
    try:
        app = _root_force_mw(app)  # type: ignore[name-defined]
    except Exception:
        # no rompas el entrypoint si el mw falla
        pass

# --- Guard final: garantiza que 'app' exista a nivel módulo ---
try:
    app  # noqa: F821
except NameError:
    try:
        _app = _resolve_app()  # type: ignore[name-defined]
    except Exception:
        _app = None
    try:
        app = _middleware(_app, is_fallback=(_app is None))  # type: ignore[name-defined]
    except Exception:
        # Fallback mínimo y seguro (sirve health y 404 JSON)
        def app(environ, start_response):  # type: ignore[no-redef]
            path = (environ.get("PATH_INFO") or "")
            if path == "/api/health":
                start_response("200 OK", [("Content-Type","application/json; charset=utf-8")])
                return [b'{"ok": true}']
            start_response("404 Not Found", [("Content-Type","application/json; charset=utf-8")])
            return [b'{"ok": false, "error": "not_found"}']
