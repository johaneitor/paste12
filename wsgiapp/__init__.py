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

        if path == "/api/deploy-stamp" and method in ("GET","HEAD"):
            data = {
                "ok": True,
                "commit": os.environ.get("RENDER_GIT_COMMIT") or os.environ.get("COMMIT") or "",
                "stamp": os.environ.get("DEPLOY_STAMP") or "",
            }
            status, headers, body = _json(200, data)
            return _finish(start_response, status, headers, body, method)

        if path in ("/api/notes", "/api/notes_fallback") and method in ("GET","HEAD"):
            code, payload, nxt = _notes_query(qs)
            status, headers, body = _json(code, payload)
            extra = []
            if nxt and nxt.get("cursor_ts") and nxt.get("cursor_id"):
                from urllib.parse import quote
                ts_q = quote(str(nxt["cursor_ts"]), safe="")
                link = f'</api/notes?cursor_ts={ts_q}&cursor_id={nxt["cursor_id"]}>; rel="next"'
                extra.append(("Link", link))
                extra.append(("X-Next-Cursor", json.dumps(nxt)))
            return _finish(start_response, status, headers, body, method, extra_headers=extra)

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

                    # Like con dedupe 1×persona (log + índice único)

                    try:

                        from sqlalchemy import text as _text

                        with _engine().begin() as cx:

                            # Tabla e índice (no-op si existen)

                            try:

                                cx.execute(_text("""

                                    CREATE TABLE IF NOT EXISTS like_log(

                                        id SERIAL PRIMARY KEY,

                                        note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,

                                        fingerprint VARCHAR(128) NOT NULL,

                                        created_at TIMESTAMPTZ DEFAULT NOW()

                                    )

                                """))

                                cx.execute(_text("""

                                    CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp

                                    ON like_log(note_id, fingerprint)

                                """))

                            except Exception:

                                pass

                            fp = _fingerprint(environ)

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

                            likes  = int(row[0] or 0)

                            views  = int(row[1] or 0)

                            reports= int(row[2] or 0)

                        code, payload = 200, {"ok": True, "id": note_id, "likes": likes, "views": views, "reports": reports, "deduped": (not inserted)}

                    except Exception as e:

                        code, payload = 500, {"ok": False, "error": str(e)}

                elif action == "view":

                    code, payload = _inc_simple(note_id, "views")

                elif action == "report":

                    try:

                        import os

                        threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")

                    except Exception:

                        threshold = 5

                    fp = _fingerprint(environ)

                    try:

                        code, payload = _report_once(note_id, fp, threshold)

                    except Exception as e:

                        code, payload = 500, {"ok": False, "error": f"report_failed: {e}"}

                else:

                    code, payload = 404, {"ok": False, "error": "unknown_action"}

                status, headers, body = _json(code, payload)

                return _finish(start_response, status, headers, body, method)

        if path.startswith("/api/notes/") and method == "GET":
            tail = path.removeprefix("/api/notes/")
            try:
                note_id = int(tail)
            except Exception:
                note_id = None
            if note_id:
                from sqlalchemy import text as _text
                with _engine().begin() as cx:
                    cols = _columns(cx)
                    sel = _build_select(cols, with_where=False) + " OFFSET 0"
                    row = cx.execute(_text(f"SELECT * FROM ({sel}) x WHERE id=:id"), {"id": note_id, "lim": 1}).mappings().first()
                    if not row:
                        status, headers, body = _json(404, {"ok": False, "error": "not_found"})
                    else:
                        status, headers, body = _json(200, {"ok": True, "item": _normalize_row(dict(row))})
                return _finish(start_response, status, headers, body, method)

        if inner_app is not None:
            return inner_app(environ, start_response)
        status, headers, body = _json(404, {"ok": False, "error": "not_found"})
        return _finish(start_response, status, headers, body, method)
    return _app

_app = _resolve_app()
app  = _middleware(_app, is_fallback=(_app is None))
try:
    _root_force_mw  # noqa
except NameError:
    pass
else:
    try:
        app = _root_force_mw(app)
    except Exception:
        pass




# --- middleware final: fuerza '/' desde el bridge si FORCE_BRIDGE_INDEX está activo ---
def _root_force_mw(inner):
    def _mw(environ, start_response):
        path   = environ.get("PATH_INFO", "") or ""
        method = (environ.get("REQUEST_METHOD", "GET") or "GET").upper()
        _force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        if _force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # Garantizar no-store y marcar fuente
            headers = [(k, v) for (k, v) in headers if k.lower() != "cache-control"]
            headers += [
                ("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source", "bridge"),
            ]
            return _finish(start_response, status, headers, body, method)
        return inner(environ, start_response)
    return _mw


class _ForceRootIndexWrapper:
    def __init__(self, inner):
        self.inner = inner
    def __call__(self, environ, start_response):
        try:
            force = os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")
        except Exception:
            force = False
        if force:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if path in ("/","/index.html") and method in ("GET","HEAD"):
                status, headers, body = _serve_index_html()
                # Garantizar no-store y marcar fuente
                headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                headers += [
                    ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                    ("X-Index-Source","bridge"),
                ]
                return _finish(start_response, status, headers, body, method)
        return self.inner(environ, start_response)


# --- forzar raíz desde bridge cuando se habilita FORCE_BRIDGE_INDEX ---
app = _ForceRootIndexWrapper(app)
FORCE_ROOT_WRAPPED = True


# === APPEND-ONLY: diagnóstico del bridge en /api/bridge-state ===
class _BridgeDiagWrapper:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        if path == "/api/bridge-state":
            import os, json, hashlib, os as _os
            # Variables de entorno relevantes
            force_env  = os.getenv("FORCE_BRIDGE_INDEX","")
            force_bool = force_env.strip().lower() in ("1","true","yes","on")
            override   = os.environ.get("WSGI_BRIDGE_INDEX") or ""

            # Resolver repo y candidatos a index
            try:
                _REPO_DIR2 = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
            except Exception:
                _REPO_DIR2 = ""

            cands = [override] if override else [
                _os.path.join(_REPO_DIR2, "backend", "static", "index.html"),
                _os.path.join(_REPO_DIR2, "public",  "index.html"),
                _os.path.join(_REPO_DIR2, "frontend","index.html"),
                _os.path.join(_REPO_DIR2, "index.html"),
            ]

            resolved = None; size = None; sha256 = None; pastel = False
            try:
                for pth in cands:
                    if pth and _os.path.isfile(pth):
                        resolved = pth
                        size = _os.path.getsize(pth)
                        with open(pth,"rb") as f:
                            data = f.read()
                        sha256 = hashlib.sha256(data).hexdigest()
                        pastel = (b'--teal:#8fd3d0' in data)
                        break
            except Exception:
                pass

            data = {
                "ok": True,
                "force_env": force_env,
                "force_bool": force_bool,
                "WSGI_BRIDGE_INDEX": override,
                "resolved_index": resolved,
                "resolved_size": size,
                "resolved_sha256": sha256,
                "resolved_has_pastel_token": pastel,
            }
            body = json.dumps(data, default=str).encode("utf-8")
            headers = [("Content-Type","application/json; charset=utf-8"),
                       ("Content-Length","0" if method=="HEAD" else str(len(body)))]
            start_response("200 OK", headers)
            return [b"" if method=="HEAD" else body]

        return self.inner(environ, start_response)

# envolver como outermost
app = _BridgeDiagWrapper(app)


# === OUTERMOST WRAPPER: fuerza '/' desde el bridge + diagnóstico en /api/bridge-state ===
class _RootBridgeAndDiag:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path   = (environ.get("PATH_INFO","") or "")
        method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()

        # --- diagnóstico ligero ---
        if path == "/api/bridge-state":
            import os, json, hashlib
            # detectar index que ve el bridge
            override = os.environ.get("WSGI_BRIDGE_INDEX") or ""
            try:
                _REPO_DIR = __import__("os").path.dirname(__import__("os").path.dirname(__file__))
            except Exception:
                _REPO_DIR = ""
            cands = [override] if override else [
                __import__("os").path.join(_REPO_DIR, "backend", "static", "index.html"),
                __import__("os").path.join(_REPO_DIR, "public",  "index.html"),
                __import__("os").path.join(_REPO_DIR, "frontend","index.html"),
                __import__("os").path.join(_REPO_DIR, "index.html"),
            ]
            resolved = None; size = None; sha256 = None; pastel = False
            try:
                for pth in cands:
                    if pth and __import__("os").path.isfile(pth):
                        resolved = pth
                        with open(pth, "rb") as f:
                            data = f.read()
                        size = len(data)
                        sha256 = hashlib.sha256(data).hexdigest()
                        pastel = (b'--teal:#8fd3d0' in data)
                        break
            except Exception:
                pass
            data = {
                "ok": True,
                "force_env": os.getenv("FORCE_BRIDGE_INDEX",""),
                "force_bool": (os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")),
                "WSGI_BRIDGE_INDEX": override,
                "resolved_index": resolved,
                "resolved_size": size,
                "resolved_sha256": sha256,
                "resolved_has_pastel_token": pastel,
            }
            body = json.dumps(data, default=str).encode("utf-8")
            headers = [("Content-Type","application/json; charset=utf-8"),
                       ("Content-Length","0" if method=="HEAD" else str(len(body)))]
            start_response("200 OK", headers)
            return [b"" if method=="HEAD" else body]

        # --- forzar raíz desde el bridge si se pide explícitamente ---
        try:
            force = ( __import__("os").getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on") )
        except Exception:
            force = False
        if force and path in ("/","/index.html") and method in ("GET","HEAD"):
            status, headers, body = _serve_index_html()
            # asegurar no-store y marcar fuente
            headers = [(k,v) for (k,v) in headers if k.lower()!="cache-control"]
            headers += [
                ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
                ("X-Index-Source","bridge"),
            ]
            return _finish(start_response, status, headers, body, method)

        return self.inner(environ, start_response)


# --- aplicar wrapper de raíz/diag como capa más externa ---
app = _RootBridgeAndDiag(app)

# === APPEND-ONLY: Guard de likes 1×persona (dedupe con log) ===
class _LikesGuard:
    def __init__(self, inner):
        self.inner = inner

    def _fp(self, environ):
        import hashlib
        fp = (environ.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        parts = [
            (environ.get("HTTP_X_FORWARDED_FOR","").split(",")[0] or "").strip(),
            (environ.get("REMOTE_ADDR","") or "").strip(),
            (environ.get("HTTP_USER_AGENT","") or "").strip(),
        ]
        raw = "|".join(parts).encode("utf-8","ignore")
        return hashlib.sha256(raw).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("X-WSGI-Bridge","1"),
        ])
        return [body]

    def _bootstrap_like_log(self, cx):
        from sqlalchemy import text as _text
        try:
            cx.execute(_text("""
                CREATE TABLE IF NOT EXISTS like_log(
                    id SERIAL PRIMARY KEY,
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                )
            """))
        except Exception:
            pass
        try:
            cx.execute(_text("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                ON like_log(note_id, fingerprint)
            """))
        except Exception:
            pass

    def _handle_like(self, environ, start_response, note_id):
        from sqlalchemy import text as _text
        import os
        enabled = (environ.get("ENABLE_LIKES_DEDUPE")
                   or os.getenv("ENABLE_LIKES_DEDUPE","1")).strip().lower() in ("1","true","yes","on")
        if not enabled:
            return self.inner(environ, start_response)
        try:
            from wsgiapp.__init__ import _engine
            eng = _engine()
            fp = self._fp(environ)
            with eng.begin() as cx:
                self._bootstrap_like_log(cx)

                inserted = False
                try:
                    cx.execute(_text(
                        "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                    ), {"id": note_id, "fp": fp})
                    inserted = True
                except Exception:
                    inserted = False

                if inserted:
                    cx.execute(_text(
                        "UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})

                row = cx.execute(_text(
                    "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()

                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})

                return self._json(start_response, 200, {
                    "ok": True,
                    "id": row["id"],
                    "likes": row["likes"],
                    "views": row["views"],
                    "reports": row["reports"],
                    "deduped": (not inserted),
                })

        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                seg = path[len("/api/notes/"):-len("/like")]
                try:
                    nid = int(seg.strip("/"))
                except Exception:
                    nid = None
                if nid:
                    return self._handle_like(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)

# Envolver app (idempotente)
try:
    app = _LikesGuard(app)
except Exception:
    pass

# === APPEND-ONLY: Guard final de likes 1×persona (CDN-friendly) ===
class _LikesGuardFinal:
    def __init__(self, inner):
        self.inner = inner

    def _fp(self, env):
        fp = (env.get("HTTP_X_FP") or "").strip()
        if fp:
            return fp[:128]
        ip = (
            (env.get("HTTP_CF_CONNECTING_IP") or "").strip()
            or (env.get("HTTP_TRUE_CLIENT_IP") or "").strip()
            or (env.get("HTTP_X_REAL_IP") or "").strip()
            or (env.get("HTTP_X_FORWARDED_FOR") or "").split(",")[0].strip()
            or (env.get("REMOTE_ADDR") or "").strip()
        )
        ua = (env.get("HTTP_USER_AGENT") or "").strip()
        raw = f"{ip}|{ua}".encode("utf-8","ignore")
        import hashlib
        return hashlib.sha256(raw).hexdigest()

    def _json(self, start_response, code, payload):
        import json
        body = json.dumps(payload, default=str).encode("utf-8")
        start_response(f"{code} OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(body))),
            ("Cache-Control","no-store, no-cache, must-revalidate, max-age=0"),
        ])
        return [body]

    def _bootstrap(self, cx):
        from sqlalchemy import text as T
        try:
            cx.execute(T("""
                CREATE TABLE IF NOT EXISTS like_log(
                  id SERIAL PRIMARY KEY,
                  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                  fingerprint VARCHAR(128) NOT NULL,
                  created_at TIMESTAMPTZ DEFAULT NOW()
                );
            """))
        except Exception:
            pass
        try:
            cx.execute(T("""
                CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                  ON like_log(note_id, fingerprint);
            """))
        except Exception:
            pass

    def _handle(self, env, start_response, note_id):
        try:
            from sqlalchemy import text as T
            from wsgiapp.__init__ import _engine
            fp = self._fp(env)
            with _engine().begin() as cx:
                self._bootstrap(cx)
                inserted = False
                try:
                    cx.execute(T(
                      "INSERT INTO like_log(note_id, fingerprint) VALUES (:id,:fp)"
                    ), {"id": note_id, "fp": fp})
                    inserted = True
                except Exception:
                    inserted = False
                if inserted:
                    cx.execute(T(
                      "UPDATE note SET likes=COALESCE(likes,0)+1 WHERE id=:id"
                    ), {"id": note_id})
                row = cx.execute(T(
                  "SELECT id, COALESCE(likes,0) AS likes, COALESCE(views,0) AS views, COALESCE(reports,0) AS reports FROM note WHERE id=:id"
                ), {"id": note_id}).mappings().first()
                if not row:
                    return self._json(start_response, 404, {"ok": False, "error": "not_found"})
                return self._json(start_response, 200, {
                    "ok": True, "id": row["id"],
                    "likes": row["likes"], "views": row["views"], "reports": row["reports"],
                    "deduped": (not inserted),
                })
        except Exception as e:
            return self._json(start_response, 500, {"ok": False, "error": str(e)})

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            method = (environ.get("REQUEST_METHOD","GET") or "GET").upper()
            if method == "POST" and path.startswith("/api/notes/") and path.endswith("/like"):
                mid = path[len("/api/notes/"):-len("/like")]
                try:
                    nid = int(mid.strip("/"))
                except Exception:
                    nid = None
                if nid:
                    return self._handle(environ, start_response, nid)
        except Exception:
            pass
        return self.inner(environ, start_response)

# --- envolver outermost: likes guard final ---
try:
    _LIKES_GUARD_FINAL
except NameError:
    try:
        app = _LikesGuardFinal(app)
    except Exception:
        pass
    _LIKES_GUARD_FINAL = True

# === PATCH:likes_dedupe BEGIN ===
# Parche encapsulado: apagado por defecto. Actívalo con ENABLE_PATCH_LIKES_DEDUPE=1
class _Patch_likes_dedupe:
    def __init__(self, inner):
        self.inner = inner

    def _enabled(self, environ):
        val = (environ.get("ENABLE_PATCH_LIKES_DEDUPE") or "") or (environ.get("HTTP_ENABLE_PATCH_LIKES_DEDUPE") or "")
        return str(val).strip().lower() in ("1","true","yes","on")

    def __call__(self, environ, start_response):
        try:
            if not self._enabled(environ):
                return self.inner(environ, start_response)
            path = (environ.get("PATH_INFO","") or "")
            # Encapsulación por prefijo exacto (no toca otras rutas)
            if path.startswith("/api/notes"):
                # >>>>>>>>>>>>>>> ZONA DE PARCHE (edita aquí) <<<<<<<<<<<<<<<
                # Por defecto, no hace nada: deja pasar tal cual.
                # Ejemplo: podrías leer/reescribir headers o desviar a un handler específico.
                # return tu_handler(environ, start_response)
                # -----------------------------------------------------------
                pass
        except Exception:
            # Pase seguro ante errores del parche
            pass
        return self.inner(environ, start_response)

# Envolver una sola vez (outermost, reversible quitando este bloque)
try:
    _PATCH_WRAPPED_LIKES_DEDUPE
except NameError:
    try:
        app = _Patch_likes_dedupe(app)
    except Exception:
        pass
    _PATCH_WRAPPED_LIKES_DEDUPE = True
# === PATCH:likes_dedupe END ===

# === APPEND-ONLY: Max TTL guard (cap hours to 3 months by default) ===
class _MaxTTLGuard:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method == "POST" and path == "/api/notes":
                import os, json, io
                # reversible por ENV
                if (environ.get("HTTP_DISABLE_MAX_TTL") or os.getenv("DISABLE_MAX_TTL","0")).strip().lower() in ("1","true","yes","on"):
                    return self.inner(environ, start_response)
                try:
                    max_h = int((environ.get("HTTP_MAX_TTL_HOURS") or os.getenv("MAX_TTL_HOURS","2160")).strip() or "2160")
                except Exception:
                    max_h = 2160
                ctype = (environ.get("CONTENT_TYPE") or "").lower()
                if "application/json" in ctype:
                    try:
                        length = int(environ.get("CONTENT_LENGTH") or "0")
                    except Exception:
                        length = 0
                    raw = environ["wsgi.input"].read(length) if length > 0 else b"{}"
                    try:
                        data = json.loads(raw.decode("utf-8") or "{}")
                    except Exception:
                        data = {}
                    # clamp defensivo de nombres comunes
                    keys = ("hours","expires_hours","ttl","ttl_hours")
                    touched = False
                    for k in keys:
                        if isinstance(data.get(k), (int, float)):
                            v = int(data[k])
                            if v < 1: v = 1
                            if v > max_h: v = max_h
                            data[k] = v
                            touched = True
                    if touched:
                        nr = json.dumps(data, ensure_ascii=False).encode("utf-8")
                        environ["wsgi.input"] = io.BytesIO(nr)
                        environ["CONTENT_LENGTH"] = str(len(nr))
                        def sr(status, headers, exc_info=None):
                            headers = list(headers) + [("X-Max-TTL-Hours", str(max_h))]
                            return start_response(status, headers, exc_info)
                        return self.inner(environ, sr)
        except Exception:
            pass
        return self.inner(environ, start_response)

# --- envolver outermost: Max TTL guard ---
try:
    _MAX_TTL_WRAPPED
except NameError:
    try:
        app = _MaxTTLGuard(app)
    except Exception:
        pass
    _MAX_TTL_WRAPPED = True


# === APPEND-ONLY: Summary preview para notas (20 chars + '…', con 'ver más' en UI) ===
class _SummaryPreviewWrapper:
    def __init__(self, inner):
        self.inner = inner

    def _is_enabled(self, environ):
        def _truth(v):
            return (v or "").strip().lower() in ("1","true","yes","on")
        # header tiene prioridad para poder desactivar sin redeploy
        if _truth(environ.get("HTTP_DISABLE_SUMMARY_PREVIEW")):
            return False
        # env (default on)
        import os
        if "DISABLE_SUMMARY_PREVIEW" in os.environ:
            return not _truth(os.environ.get("DISABLE_SUMMARY_PREVIEW"))
        return True

    def _limit(self, environ):
        import os
        hdr = environ.get("HTTP_SUMMARY_PREVIEW_LIMIT")
        if hdr and hdr.isdigit():
            return max(1, min(500, int(hdr)))
        env = os.environ.get("SUMMARY_PREVIEW_LIMIT")
        if env and env.isdigit():
            return max(1, min(500, int(env)))
        return 20

    def _add_summary(self, obj, limit):
        # obj puede ser {"items":[...]}, o {"item":{...}}
        def _mk(txt: str) -> str:
            txt = txt or ""
            return txt if len(txt) <= limit else (txt[:limit] + "…")
        if isinstance(obj, dict):
            if "items" in obj and isinstance(obj["items"], list):
                for it in obj["items"]:
                    if isinstance(it, dict):
                        if "summary" not in it or not it.get("summary"):
                            base = it.get("text") or it.get("content") or ""
                            it["summary"] = _mk(base)
                            # pista opcional para UI
                            it.setdefault("has_more", len(base) > limit)
            if "item" in obj and isinstance(obj["item"], dict):
                it = obj["item"]
                if "summary" not in it or not it.get("summary"):
                    base = it.get("text") or it.get("content") or ""
                    it["summary"] = _mk(base)
                    it.setdefault("has_more", len(base) > limit)
        return obj

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        # sólo GET /api/notes...
        if method == "GET" and path.startswith("/api/notes"):
            if not self._is_enabled(environ):
                return self.inner(environ, start_response)

            status_headers = {}
            def _cap_sr(status, headers, exc_info=None):
                status_headers["status"] = status
                status_headers["headers"] = headers[:]
                return start_response(status, headers, exc_info)

            # llamamos a la app interna
            app_iter = self.inner(environ, _cap_sr)

            try:
                body = b"".join(app_iter)
            finally:
                try:
                    close = getattr(app_iter, "close", None)
                    if callable(close):
                        close()
                except Exception:
                    pass

            status = status_headers.get("status","200 OK")
            headers = status_headers.get("headers", [])

            # Sólo si es JSON y 200
            ct = next((v for (k,v) in headers if k.lower()=="content-type"), "application/json").lower()
            if "200" in status and "application/json" in ct:
                try:
                    obj = json.loads(body.decode("utf-8"))
                    lim = self._limit(environ)
                    new = self._add_summary(obj, lim)
                    new_body = json.dumps(new, ensure_ascii=False, separators=(",",":")).encode("utf-8")
                    # actualizar Content-Length y marcar headers
                    new_headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
                    new_headers.append(("Content-Length", str(len(new_body))))
                    new_headers.append(("X-Summary-Applied","1"))
                    new_headers.append(("X-Summary-Limit", str(lim)))
                    def _sr2(status, hdrs, exc_info=None):
                        return start_response(status, new_headers, exc_info)
                    return [new_body]
                except Exception:
                    # ante cualquier error, devolvemos intacto
                    return [body]
            else:
                return [body]
        # resto pasa directo
        return self.inner(environ, start_response)

# --- envolver outermost (summary preview) ---
try:
    SUMMARY_PREVIEW_WRAPPED
except NameError:
    try:
        app = _SummaryPreviewWrapper(app)
    except Exception:
        pass
    SUMMARY_PREVIEW_WRAPPED = True


# === APPEND-ONLY: Summary preview V2 (fix Content-Length y start_response) ===
class _SummaryPreviewWrapperV2:
    def __init__(self, inner):
        self.inner = inner

    def _truth(self, v:str):
        return (v or "").strip().lower() in ("1","true","yes","on")

    def _enabled(self, env):
        if self._truth(env.get("HTTP_DISABLE_SUMMARY_PREVIEW")):
            return False
        import os
        if "DISABLE_SUMMARY_PREVIEW" in os.environ:
            return not self._truth(os.environ.get("DISABLE_SUMMARY_PREVIEW"))
        return True

    def _limit(self, env):
        import os
        h = env.get("HTTP_SUMMARY_PREVIEW_LIMIT")
        if h and h.isdigit(): return max(1, min(500, int(h)))
        e = os.environ.get("SUMMARY_PREVIEW_LIMIT")
        if e and e.isdigit(): return max(1, min(500, int(e)))
        return 20

    def _mk_summary(self, txt, lim):
        txt = txt or ""
        return txt if len(txt) <= lim else (txt[:lim] + "…")

    def _apply(self, obj, lim):
        if isinstance(obj, dict):
            if "items" in obj and isinstance(obj["items"], list):
                for it in obj["items"]:
                    if isinstance(it, dict):
                        if not it.get("summary"):
                            base = it.get("text") or it.get("content") or ""
                            it["summary"] = self._mk_summary(base, lim)
                            it.setdefault("has_more", len(base) > len(it["summary"]))
            if "item" in obj and isinstance(obj["item"], dict):
                it = obj["item"]
                if not it.get("summary"):
                    base = it.get("text") or it.get("content") or ""
                    it["summary"] = self._mk_summary(base, lim)
                    it.setdefault("has_more", len(base) > len(it["summary"]))
        return obj

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        method = (environ.get("REQUEST_METHOD") or "GET").upper()

        # Sólo afecta GET /api/notes...
        if method == "GET" and path.startswith("/api/notes"):
            if not self._enabled(environ):
                return self.inner(environ, start_response)

            captured = {"status": None, "headers": []}
            chunks = []

            def fake_start(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers)
                # write() collector (por si el inner lo usa)
                def _w(b):
                    chunks.append(b)
                return _w

            app_iter = self.inner(environ, fake_start)
            try:
                for c in app_iter:
                    chunks.append(c)
            finally:
                try:
                    close = getattr(app_iter, "close", None)
                    if callable(close): close()
                except Exception:
                    pass

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []
            body = b"".join(chunks)

            # Si no es 200 o no es JSON -> devolvemos tal cual pero re-empaquetado
            ct = next((v for (k,v) in headers if k.lower()=="content-type"), "application/json; charset=utf-8").lower()
            if "200" not in status or "application/json" not in ct:
                start_response(status, headers)
                return [body]

            # Reescritura segura del cuerpo y Content-Length
            try:
                obj = json.loads(body.decode("utf-8"))
                lim = self._limit(environ)
                obj2 = self._apply(obj, lim)
                new_body = json.dumps(obj2, ensure_ascii=False, separators=(",",":")).encode("utf-8")
                # headers: reemplazar Content-Length y agregar marcas
                new_headers = [(k,v) for (k,v) in headers if k.lower()!="content-length"]
                new_headers.append(("Content-Length", str(len(new_body))))
                new_headers.append(("X-Summary-Applied","1"))
                new_headers.append(("X-Summary-Limit", str(lim)))
                start_response(status, new_headers)
                return [new_body]
            except Exception:
                # ante error, devolvemos intacto
                start_response(status, headers)
                return [body]

        # resto pasa directo
        return self.inner(environ, start_response)

# --- envolver outermost (summary preview V2) ---
try:
    SUMMARY_PREVIEW_WRAPPED_V2
except NameError:
    try:
        app = _SummaryPreviewWrapperV2(app)
    except Exception:
        pass
    SUMMARY_PREVIEW_WRAPPED_V2 = True


# === APPEND-ONLY: Guard para /api/deploy-stamp (a prueba de fallos) ===
class _DeployStampGuard:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        try:
            path   = (environ.get("PATH_INFO") or "")
            method = (environ.get("REQUEST_METHOD") or "GET").upper()
            if method == "GET" and path == "/api/deploy-stamp":
                commit = (os.environ.get("RENDER_GIT_COMMIT")
                          or os.environ.get("COMMIT")
                          or os.environ.get("GIT_COMMIT")
                          or "")
                # Intentamos leer .deploystamp si existe
                stamp = ""
                try:
                    import pathlib
                    f = pathlib.Path(".deploystamp")
                    if f.exists():
                        stamp = f.read_text(encoding="utf-8").strip()
                except Exception:
                    pass
                body = json.dumps({"ok": True, "commit": commit, "stamp": stamp}).encode("utf-8")
                start_response("200 OK", [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("X-WSGI-Bridge","1"),
                ])
                return [body]
        except Exception:
            # si algo pasa, seguimos al inner
            pass
        return self.inner(environ, start_response)

# --- envolver outermost: deploy-stamp guard ---
try:
    DEPLOYSTAMP_GUARD_WRAPPED
except NameError:
    try:
        app = _DeployStampGuard(app)
    except Exception:
        pass
    DEPLOYSTAMP_GUARD_WRAPPED = True
