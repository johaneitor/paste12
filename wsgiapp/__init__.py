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

    # Si FORCE_BRIDGE_INDEX está activo, devolvemos un index pastel inline
    if (os.getenv("FORCE_BRIDGE_INDEX","").strip().lower() in ("1","true","yes","on")):
        _html_pastel = """<!doctype html>
<html lang="es"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Notas</title>
<style>
  :root{
    --bg:#fffdfc; --fg:#24323f; --muted:#6b7a86;
    --teal:#8fd3d0; /* turquesa pastel (token para check) */
    --peach:#ffb38a; --pink:#f9a3c7; --card:#ffffff; --ring: rgba(36,50,63,.15);
  }
  *{box-sizing:border-box} body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:linear-gradient(180deg,var(--bg),#fff);color:var(--fg)}
  header{position:sticky;top:0;z-index:10;background:linear-gradient(90deg,var(--teal),var(--peach),var(--pink));color:#17323a;padding:16px 20px;box-shadow:0 2px 12px var(--ring)}
  h1{margin:0;font-size:clamp(20px,3.2vw,28px)} .container{max-width:860px;margin:20px auto;padding:0 16px}
  .card{background:var(--card);border:1px solid #eee;border-radius:16px;padding:14px;box-shadow:0 4px 20px var(--ring)}
  textarea,input[type="text"]{width:100%;padding:12px 14px;border-radius:12px;border:1px solid #e6eef2;outline:none;font-size:16px;background:#fff;color:var(--fg)}
  textarea:focus,input:focus{border-color:#b5dfe0;box-shadow:0 0 0 4px rgba(143,211,208,.25)}
  .row{display:flex;gap:10px;margin-top:10px}
  .btn{appearance:none;border:0;border-radius:12px;padding:12px 16px;font-weight:600;cursor:pointer;background:linear-gradient(90deg,var(--teal),var(--peach));color:#14333a;box-shadow:0 6px 18px var(--ring)}
  .list{margin-top:18px;display:grid;gap:12px}
  .note{background:#fff;border:1px solid #eef2f5;border-radius:14px;padding:12px 14px}
  .note .meta{color:var(--muted);font-size:12px;margin-top:6px}
  .menu{margin-top:8px} .hidden{display:none} .error{color:#9a2b2b;margin-top:8px} .ok{color:#0a6f57;margin-top:8px}
  footer{margin:40px 0 28px;color:var(--muted);text-align:center;font-size:14px}
  footer a{color:#0b7c8a;text-decoration:underline}
</style>
</head>
<body>
  <header><h1>Notas</h1></header>
  <main class="container">
    <section class="card">
      <label for="text" style="font-weight:600;">Escribe tu nota…</label>
      <textarea id="text" rows="3" placeholder="Escribe tu nota…"></textarea>
      <div class="row">
        <input id="ttl" type="text" inputmode="numeric" pattern="[0-9]*" placeholder="Horas (12 por defecto)">
        <button id="send" class="btn">Publicar</button>
      </div>
      <div id="msg" class="hidden"></div>
    </section>
    <section class="list" id="list"></section>
    <footer>
      <span>Usamos cookies/localStorage (p.ej., para contar vistas).</span><br/>
      <a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a>
    </footer>
  </main>
<script>
const $ = (s)=>document.querySelector(s);
const api = (p)=> (p.startsWith('/')?p:'/api/'+p);
function fmtDate(iso){ try{ return new Date(iso).toLocaleString(); }catch(_){ return iso } }
function renderItem(it){
  const text = it.text || it.content || it.summary || '';
  return `
    <article class="note" data-id="${it.id}">
      <div>${text ? text.replace(/</g,'&lt;') : '(sin texto)'}</div>
      <div class="meta">
        #${it.id ?? '-'} · ${fmtDate(it.timestamp)}
        · <button class="act like">❤ ${it.likes ?? 0}</button>
        · <span class="views">👁️ ${it.views ?? 0}</span>
        · <button class="act more">⋯</button>
      </div>
      <div class="menu hidden">
        <button class="share">Compartir</button>
        <button class="report">Reportar 🚩</button>
      </div>
    </article>`;
}
function renderList(items){ $('#list').innerHTML = (items||[]).map(renderItem).join('') || '<div class="note">No hay notas aún.</div>'; }
async function load(){ try{ const r=await fetch(api('notes')); const j=await r.json(); renderList(Array.isArray(j)?j:(j.items||[])); }catch(e){ $('#list').innerHTML='<div class="note">Error cargando notas.</div>'; } }
async function publish(){
  const text = $('#text').value.trim(); const ttlh = parseInt($('#ttl').value.trim()||'');
  if(!text){ flash('Escribí algo antes de publicar', false); return }
  try{
    const body = { text }; if(Number.isFinite(ttlh) && ttlh>0) body.ttl_hours = ttlh;
    const r = await fetch(api('notes'), { method:'POST', headers:{'Content-Type':'application/json','Accept':'application/json'}, body: JSON.stringify(body)});
    const j = await r.json(); if(!r.ok || !j.ok) throw new Error(j.error||'error');
    $('#text').value=''; $('#ttl').value=''; flash('Publicado ✅', true);
    const it = j.item || null; if(it){ const cur=$('#list').innerHTML; $('#list').innerHTML = renderItem(it)+cur; } else { load(); }
  }catch(e){ flash('No se pudo publicar', false); }
}
function flash(msg, ok){ const el=$('#msg'); el.className = ok?'ok':'error'; el.textContent = msg; setTimeout(()=>{ el.className='hidden'; el.textContent=''; }, 2000); }
$('#send').addEventListener('click', publish);
$('#text').addEventListener('keydown', (e)=>{ if(e.key==='Enter' && (e.ctrlKey||e.metaKey)){ publish(); }});
window.addEventListener('DOMContentLoaded', ()=>{ const u = new URL(location.href); const pre=u.searchParams.get('text'); if(pre){ $('#text').value = pre; } load(); });
</script>
</body></html>"""
        status, headers, body = _html(200, _html_pastel)
        headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
        return status, headers, body
    override = os.environ.get("WSGI_BRIDGE_INDEX")
    candidates = [override] if override else [
        os.path.join(_REPO_DIR, "public", "index.html"),
        os.path.join(_REPO_DIR, "frontend", "index.html"),
        os.path.join(_REPO_DIR, "backend", "static", "index.html"),
        os.path.join(_REPO_DIR, "index.html"),
    ]
    for p in candidates:
        if p and os.path.isfile(p):
            body = _try_read(p)
            if body is not None:
                ctype = mimetypes.guess_type(p)[0] or "text/html"
                status, headers, body = _html(200, body.decode("utf-8", "ignore"), f"{ctype}; charset=utf-8")
                headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
                return status, headers, body
    html = """<!doctype html><html><head><meta charset="utf-8"><title>paste12</title></head>
<body style="font-family: system-ui, sans-serif; margin: 2rem;">
<h1>paste12</h1><p>Backend vivo (bridge fallback).</p>
<ul>
  <li><a href="/api/notes">/api/notes</a></li>
  <li><a href="/api/notes_fallback">/api/notes_fallback</a></li>
  <li><a href="/api/notes_diag">/api/notes_diag</a></li>
  <li><a href="/api/deploy-stamp">/api/deploy-stamp</a></li>
</ul></body></html>"""
    status, headers, body = _html(200, html)
            headers = list(headers) + [("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")]
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
                note_id = None; action = ""
            if note_id:
                if action == "like":
                    code, payload = _inc_simple(note_id, "likes")
                elif action == "view":
                    code, payload = _inc_simple(note_id, "views")
                elif action == "report":
                    threshold = int(os.environ.get("REPORT_THRESHOLD", "5") or "5")
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
app = _root_force_mw(app)



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
