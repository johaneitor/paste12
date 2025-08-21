#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"; cd "$ROOT"
mkdir -p .tmp backend/utils

say(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }

RUNPY="run.py"
ROUTES="backend/routes.py"
MODELS="backend/models.py"
HOOK="backend/models_hooks.py"

LOG=".tmp/paste12.log"
HOOKLOG=".tmp/author_fp_hook.log"
REPORT=".tmp/paste12_doctor_report.txt"
DB="${PASTE12_DB:-app.db}"

: > "$LOG" ; : > "$HOOKLOG" ; : > "$REPORT"

[ -f "$RUNPY" ] || { warn "No encuentro $RUNPY"; exit 1; }
[ -f "$ROUTES" ] || { warn "No encuentro $ROUTES"; exit 1; }

echo "Root: $ROOT" >>"$REPORT"
echo "DB:   $DB"    >>"$REPORT"

# 1) util fingerprint
cat > backend/utils/fingerprint.py <<'PY'
import os, hashlib
from flask import request, has_request_context
def client_fingerprint() -> str:
    if not has_request_context(): return "noctx"
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent",""); salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
PY

# 2) Normalizar routes.py (sin f-strings)
say "Normalizando backend/routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Import fingerprint
if "from backend.utils.fingerprint import client_fingerprint" not in s:
    s = "from backend.utils.fingerprint import client_fingerprint\n" + s

# Borrar líneas sueltas que rompen indentación
s = re.sub(r'(?m)^\s*author_fp\s*=\s*client_fingerprint\(\)\s*,?\s*$', '', s)

# Eliminar definiciones previas de list_notes / create_note (para evitar endpoints duplicados)
def kill_func(name):
    # borra desde "def name(" hasta el siguiente "def " o "@"
    return re.sub(r'(?ms)^\s*def\s+'+name+r'\s*\(.*?(?=^\s*def\s+|^\s*@|$\Z)', '', s)

s = re.sub(r'(?ms)^\s*def\s+list_notes\s*\(.*?(?=^\s*def\s+|^\s*@|$\Z)', '', s)
s = re.sub(r'(?ms)^\s*def\s+create_note\s*\(.*?(?=^\s*def\s+|^\s*@|$\Z)', '', s)

# Detectar blueprint si existe
m_bp = re.search(r'@([A-Za-z_]\w*)\.route\(', s)
bp = m_bp.group(1) if m_bp else None
dec_get  = f"@{bp}.route('/api/notes', methods=['GET'])"  if bp else "@app.route('/api/notes', methods=['GET'])"
dec_post = f"@{bp}.route('/api/notes', methods=['POST'])" if bp else "@app.route('/api/notes', methods=['POST'])"

# Bloque con llaves escapadas (para .format)
tmpl = """
{dec_get}
def list_notes():
    from flask import request, jsonify
    try:
        page = int(request.args.get('page', 1))
    except Exception:
        page = 1
    page = max(1, page)
    try:
        q = Note.query.order_by(Note.timestamp.desc())
        items = q.limit(20).offset((page-1)*20).all()
        now = _now()
        return jsonify([_note_json(n, now) for n in items]), 200
    except Exception as e:
        return jsonify({{"error":"list_failed","detail":str(e)}}), 500

{dec_post}
def create_note():
    from flask import request, jsonify
    from datetime import timedelta
    data = request.get_json(silent=True) or {{}}
    text = (data.get('text') or '').strip()
    if not text:
        return jsonify({{"error":"text required"}}), 400
    try:
        hours = int(data.get('hours', 24))
    except Exception:
        hours = 24
    hours = min(168, max(1, hours))
    now = _now()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=client_fingerprint(),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify(_note_json(n, now)), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({{"error":"create_failed","detail":str(e)}}), 500
"""

block = tmpl.format(dec_get=dec_get, dec_post=dec_post)

if not s.endswith("\n"): s += "\n"
s += "\n" + block + "\n"
s = re.sub(r'\n{3,}', '\n\n', s)

open(p,'w',encoding='utf-8').write(s)
print("[OK] routes.py normalizado con GET/POST /api/notes")
PY

# Validar sintaxis
python -m py_compile "$ROUTES"

# 3) Hook before_insert
say "Instalando hook before_insert"
cat > "$HOOK" <<'PY'
import os, hashlib, datetime, traceback
from sqlalchemy import event
from flask import request, has_request_context

def _log(msg):
    try:
        with open(".tmp/author_fp_hook.log","a") as f:
            ts = datetime.datetime.now().isoformat(timespec="seconds")
            f.write(f"[{ts}] {msg}\n")
    except Exception:
        pass

Note=None
for modname in ("backend.models","backend.models.note"):
    try:
        mod=__import__(modname, fromlist=["*"])
        cand=getattr(mod,"Note",None)
        if cand is not None:
            Note=cand; break
    except Exception as e:
        _log(f"import fail {modname}: {e!r}")

def _fp()->str:
    if not has_request_context(): return "noctx"
    ip = (request.headers.get("X-Forwarded-For","")
          or request.headers.get("CF-Connecting-IP","")
          or (request.remote_addr or ""))
    ua = request.headers.get("User-Agent","")
    salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

if Note is not None:
    @event.listens_for(Note, "before_insert")
    def note_before_insert(mapper, connection, target):
        if not getattr(target,"author_fp",None):
            try:
                target.author_fp=_fp()
                _log("Set author_fp en before_insert")
            except Exception as ex:
                _log(f"before_insert error: {ex!r}")
PY

# 4) run.py → importar hook + limiter default + bind PORT si aplica
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  awk 'NR==1{print "import backend.models_hooks  # hooks author_fp"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
fi
if ! grep -q "RATELIMIT_STORAGE_URI" "$RUNPY"; then
  cat >> "$RUNPY" <<'PY'

# Limiter storage por defecto (silencia warning si no hay Redis)
try:
    import os
    if "RATELIMIT_STORAGE_URI" not in getattr(app, "config", {}):
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass
PY
fi
if ! grep -q 'os\.environ\.get("PORT"' "$RUNPY"; then
  cat >> "$RUNPY" <<'PY'

# Bind explícito a PORT/HOST si corres app.run directamente
try:
    import os
    _port = int(os.environ.get("PORT","8000"))
    _host = os.environ.get("HOST","0.0.0.0")
    if __name__=="__main__" and hasattr(globals().get("app",None),"run"):
        app.run(host=_host, port=_port)
        print(f"✓ Servidor en http://{_host}:{_port}")
except Exception:
    pass
PY
fi

# 5) Modelo + DB (SQLite) → asegurar columna author_fp
if [ -f "$MODELS" ] && ! grep -q "author_fp" "$MODELS"; then
  python - "$MODELS" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()
m=re.search(r'(?m)^class\s+Note\s*\([^)]*\):\s*\n',s)
if m:
    start=m.end()
    m2=re.search(r'(?m)^([ \t]+)\S',s[start:])
    indent=m2.group(1) if m2 else '    '
    m3=re.search(r'(?m)^%sdef\s' % re.escape(indent), s[start:])
    at = (m3.start()+start) if m3 else len(s)
    line = f"{indent}author_fp = db.Column(db.String(64), nullable=False, index=True)\n"
    s = s[:at] + line + s[at:]
    open(p,'w',encoding='utf-8').write(s)
PY
fi

if command -v sqlite3 >/dev/null 2>&1; then
  if [ -f "$DB" ]; then
    if ! sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$'; then
      sqlite3 "$DB" 'ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx";'
    fi
    sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS idx_note_author_fp ON note(author_fp);'
  fi
fi

# 6) Reinicio local + smoke tests
say "Reiniciando run.py (nohup) → logs en ./.tmp"
pkill -f "python .*run.py" 2>/dev/null || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 40 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || true)"
[ -z "${PORT:-}" ] && PORT=8000
echo "PORT=$PORT" >>"$REPORT"

GETC=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/api/notes?page=1" || true)
POSTC=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"text":"diag","hours":24}' "http://127.0.0.1:$PORT/api/notes" || true)
echo "GET /api/notes -> $GETC"  >>"$REPORT"
echo "POST /api/notes -> $POSTC" >>"$REPORT"

tail -n 40 "$LOG"     >>"$REPORT" 2>&1 || true
tail -n 40 "$HOOKLOG" >>"$REPORT" 2>&1 || true

# 7) Push (para redeploy Render)
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "doctor_v2: fix indent & endpoints /api/notes; author_fp hook+DB; limiter; local logs" || true
  git push -u --force-with-lease origin "$BRANCH" || warn "Push falló (revisa remoto/credenciales)"
fi

say "Listo. Revisa .tmp/paste12_doctor_report.txt"
