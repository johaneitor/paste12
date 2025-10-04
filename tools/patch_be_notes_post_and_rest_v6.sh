#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }
python - <<'PYCODE'
import io, re, textwrap, py_compile
p="wsgiapp/__init__.py"
s=io.open(p,"r",encoding="utf-8").read()

def ensure_line(s, pat, line):
    return s if re.search(pat, s, re.M) else (line+"\n"+s)

s = ensure_line(s, r'^\s*from\s+flask\s+import\s+.*\brequest\b', "from flask import request")
s = ensure_line(s, r'^\s*from\s+flask\s+import\s+.*\bjsonify\b', "from flask import jsonify")
s = ensure_line(s, r'^\s*from\s+werkzeug\.exceptions\s+import\s+NotFound\b', "from werkzeug.exceptions import NotFound")

def upsert_int(name, new_val):
    global s
    if re.search(rf'^\s*{name}\s*=\s*\d+', s, re.M):
        s = re.sub(rf'^(\s*{name}\s*=\s*)(\d+)', lambda m: f"{m.group(1)}{int(m.group(2))*2}", s, flags=re.M)
    else:
        s = f"{name} = {new_val}\n{s}"

upsert_int("CAP_LIMIT", 200)
upsert_int("TTL_HOURS", 144)

if "_p12_db_conn(" not in s:
    s += textwrap.dedent("""
    def _p12_db_conn():
        try:
            import os, psycopg2
            url = os.getenv("DATABASE_URL") or os.getenv("DATABASE_INTERNAL_URL")
            if not url:
                return None
            return psycopg2.connect(url, sslmode=os.getenv("PGSSLMODE","require"))
        except Exception:
            return None
    """)

if "_p12_create_note(" not in s:
    s += textwrap.dedent("""
    def _p12_create_note(text, ttl_hours=None, importance=None):
        cx = _p12_db_conn()
        if cx is None:
            return None
        try:
            cur = cx.cursor()
            cur.execute(
                "INSERT INTO notes (text, created_at, ttl_hours, importance) VALUES (%s, NOW(), %s, %s) RETURNING id",
                (text, ttl_hours, importance)
            )
            nid = cur.fetchone()[0]
            cx.commit(); cur.close(); cx.close()
            return int(nid)
        except Exception:
            try: cx.rollback()
            except Exception: pass
            return None
    """)

if '@app.route("/api/notes", methods=["POST","OPTIONS"]' not in s:
    s += textwrap.dedent("""
    @app.route("/api/notes", methods=["POST","OPTIONS"], endpoint="p12_notes_post")
    def _p12_notes_post():
        data = {}
        if request.is_json:
            data = request.get_json(silent=True) or {}
        else:
            try:
                data = {k: v for k, v in request.form.items()}
            except Exception:
                data = {}
        text = (data.get("text") or data.get("content") or "").strip()
        if not text:
            return jsonify(error="missing_text"), 400
        ttl = data.get("ttl"); imp = data.get("importance")
        try: ttl_i = int(ttl) if ttl not in (None,"") else None
        except Exception: ttl_i = None
        try: imp_i = int(imp) if imp not in (None,"") else None
        except Exception: imp_i = None
        nid = _p12_create_note(text, ttl_i, imp_i)
        if nid is None:
            return jsonify(ok=False, accepted=True, id=0, note="non_persistent"), 202
        return jsonify(ok=True, id=nid), 201
    """)

def rest_404_block(name, table):
    key=f'endpoint="p12_rest_{name}"'
    if key in s: return ""
    return f"""
    @app.route("/api/rest/{name}", methods=["GET","POST"], endpoint="p12_rest_{name}")
    def _p12_rest_{name}():
        id_val=None
        if request.method=="GET":
            id_val=request.args.get("id")
        else:
            if request.is_json:
                id_val=(request.get_json(silent=True) or {{}}).get("id")
            else:
                try: id_val=request.form.get("id")
                except Exception: id_val=None
        try:
            note_id=int(id_val)
        except Exception:
            raise NotFound()
        try:
            res = globals().get("_p12_bump_counter", lambda *_: None)("{table}", note_id)
        except Exception:
            res = None
        if res is None:
            raise NotFound()
        return jsonify(ok=True, id=note_id, updated=res), 200
    """

s += textwrap.dedent(rest_404_block("like","likes"))
s += textwrap.dedent(rest_404_block("report","reports"))

io.open(p,"w",encoding="utf-8").write(s)
py_compile.compile(p, doraise=True)
print("PATCH_OK", p)
PYCODE
python -m py_compile "$PY"
echo "OK: $PY compilado"
