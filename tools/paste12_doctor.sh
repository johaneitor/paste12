#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

say(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }
out="/tmp/paste12_doctor_report.txt"; : > "$out"

RUNPY="run.py"
ROUTES="backend/routes.py"
HOOK="backend/models_hooks.py"
DB="${PASTE12_DB:-app.db}"
LOG="/tmp/paste12.log"
HOOKLOG="/tmp/author_fp_hook.log"

[ -f "$RUNPY" ] || { warn "No encuentro $RUNPY"; exit 1; }
[ -f "$ROUTES" ] || { warn "No encuentro $ROUTES"; exit 1; }

say "Snapshot inicial"
git status -sb >>"$out" 2>&1 || true
echo "DB: $DB" >>"$out"
echo "Rutas: $ROUTES  |  Run: $RUNPY" >>"$out"

##############################################################################
# 1) Linter mínimo: compilar todos los .py (detecta indentaciones rotas)
##############################################################################
say "Chequeo sintaxis Python (compileall)"
find backend -type f -name "*.py" -print0 | xargs -0 -I {} python -m py_compile "{}" >>"$out" 2>&1 || true

##############################################################################
# 2) Limpiar líneas sueltas/duplicadas 'author_fp=client_fingerprint(),'
#    y normalizar la función create_note con alias POST /api/notes
##############################################################################
say "Parcheando routes.py (limpieza de indentación + create_note + alias /api/notes)"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys
path=sys.argv[1]
s=open(path,'r',encoding='utf-8').read()

# Asegurar import util
if "from backend.utils.fingerprint import client_fingerprint" not in s:
    s = "from backend.utils.fingerprint import client_fingerprint\n" + s

# LIMPIEZA: eliminar líneas sueltas de author_fp=client_fingerprint() fuera de llamadas
s = re.sub(r'(?m)^\s*author_fp\s*=\s*client_fingerprint\(\)\s*,?\s*$', '', s)

# Ubicar def create_note
m_def = re.search(r'(?m)^([ \t]*)def\s+create_note\s*\(', s)
if m_def:
    indent = m_def.group(1)
    # Rango del bloque decoradores arriba del def
    deco_block_start = s.rfind("\n", 0, m_def.start())+1
    while True:
        prev = s.rfind("\n", 0, deco_block_start-1)
        if prev < 0: break
        line = s[prev+1:deco_block_start-1]
        if line.strip().startswith("@"): deco_block_start = prev+1
        else: break
    deco_block = s[deco_block_start:m_def.start()]
    # Determinar blueprint
    import re as _re
    m_bp = _re.search(r'@([A-Za-z_][A-Za-z0-9_]*)\.route\(', deco_block)
    bp = m_bp.group(1) if m_bp else "app"

    # Encontrar final de la función (siguiente def o decorador al mismo nivel)
    pos = m_def.end(); end = len(s)
    m_next = re.search(r'(?m)^(%s(?:def\s+|@))' % re.escape(indent), s[pos:])
    if m_next:
        end = pos + m_next.start()

    # Función normalizada (mantiene helpers _now, Note, db que ya tengas)
    new_func = f'''{deco_block}@{bp}.route("/api/notes", methods=["POST"])
{indent}def create_note():
{indent}    from flask import request, jsonify
{indent}    from datetime import timedelta
{indent}    data = request.get_json(silent=True) or {{}}
{indent}    text = (data.get("text") or "").strip()
{indent}    if not text:
{indent}        return jsonify({{"error": "text required"}}), 400
{indent}    try:
{indent}        hours = int(data.get("hours", 24))
{indent}    except Exception:
{indent}        hours = 24
{indent}    hours = min(168, max(1, hours))
{indent}    now = _now()  # usa tu helper existente
{indent}    n = Note(
{indent}        text=text,
{indent}        timestamp=now,
{indent}        expires_at=now + timedelta(hours=hours),
{indent}        author_fp=client_fingerprint(),
{indent}    )
{indent}    db.session.add(n)
{indent}    db.session.commit()
{indent}    return jsonify(_note_json(n, now)), 201
'''
    s = s[:deco_block_start] + new_func + s[end:]

# En cualquier otra llamada a Note(...), si falta author_fp, lo insertamos
def patch_note_calls(text):
    out = []
    i = 0
    while True:
        m = re.search(r'\bNote\s*\(', text[i:])
        if not m:
            out.append(text[i:]); break
        start = i + m.start()
        out.append(text[i:start])
        # buscar cierre equilibrando paréntesis
        j = start; depth = 0
        while j < len(text):
            if text[j] == '(':
                depth += 1
            elif text[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        call = text[start:j]  # sin ')'
        body = call
        if "author_fp" not in call:
            # hallar indent
            ls = text.rfind('\n', 0, start) + 1
            indent = re.match(r'[ \t]*', text[ls:start]).group(0) + '    '
            # asegurar coma final
            if not re.search(r',\s*$', body.strip()):
                body = body.rstrip() + ','
            body = f"{body}\n{indent}author_fp=client_fingerprint(),"
        out.append(body)
        out.append(text[j])  # ')'
        i = j+1
    return ''.join(out)

s = patch_note_calls(s)

open(path,'w',encoding='utf-8').write(s)
print("[OK] routes.py normalizado")
PY

##############################################################################
# 3) Hook before_insert + util de fingerprint (idempotente)
##############################################################################
say "Asegurando hook before_insert y util fingerprint"
mkdir -p backend/utils

cat > backend/utils/fingerprint.py <<'PY'
import os, hashlib
from flask import request, has_request_context
def client_fingerprint() -> str:
    if not has_request_context(): return "noctx"
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent",""); salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
PY

cat > "$HOOK" <<'PY'
import os, hashlib, datetime, traceback
from sqlalchemy import event
from flask import request, has_request_context

def _log(msg):
    try:
        with open("/tmp/author_fp_hook.log","a") as f:
            ts = datetime.datetime.now().isoformat(timespec="seconds")
            f.write(f"[{ts}] {msg}\n")
    except Exception:
        pass

Note=None; errs=[]
for modname in ("backend.models","backend.models.note"):
    try:
        mod=__import__(modname, fromlist=["*"])
        cand=getattr(mod,"Note",None)
        if cand is not None:
            Note=cand; break
    except Exception as e:
        errs.append(f"{modname}: {e!r}")
if Note is None:
    _log("ERROR importando Note: " + " | ".join(errs))
else:
    _log("OK import Note: " + repr(Note))

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
        try:
            if not getattr(target,"author_fp",None):
                target.author_fp=_fp()
                _log("Set author_fp en before_insert")
        except Exception as ex:
            _log("ERROR before_insert: " + repr(ex))
            _log(traceback.format_exc())
PY

# Importar hook y fijar limiter + PORT en run.py
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  awk 'NR==1{print "import backend.models_hooks  # hooks author_fp"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
fi
if ! grep -q "RATELIMIT_STORAGE_URI" "$RUNPY"; then
  cat >> "$RUNPY" <<'PY'

# --- Limiter storage por defecto ---
try:
    import os
    if "RATELIMIT_STORAGE_URI" not in getattr(app, "config", {}):
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass
PY
fi
# Asegurar binding a PORT en run.py (para Render)
if ! grep -q "os\.environ\.get(\"PORT\"" "$RUNPY"; then
  cat >> "$RUNPY" <<'PY'

# --- Bind a PORT para Render/Prod ---
try:
    import os
    _port = int(os.environ.get("PORT", "8000"))
    _host = os.environ.get("HOST", "0.0.0.0")
    if __name__ == "__main__" and hasattr(globals().get("app", None),"run"):
        app.run(host=_host, port=_port)
        print(f"✓ Servidor en http://{_host}:{_port}")
except Exception:
    pass
PY
fi

##############################################################################
# 4) Verificación/migración de DB: columna author_fp obligatoria
##############################################################################
if command -v sqlite3 >/dev/null 2>&1; then
  say "Chequeando esquema SQLite para tabla note"
  if [ -f "$DB" ]; then
    cols="$(sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | tr '\n' ' ')"
    echo "note columnas: $cols" >>"$out"
    if ! sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$'; then
      say "Agrego columna author_fp NOT NULL con default 'noctx'"
      sqlite3 "$DB" 'ALTER TABLE note ADD COLUMN author_fp TEXT NOT NULL DEFAULT "noctx";'
    fi
    say "Creo índice idx_note_author_fp (si no existe)"
    sqlite3 "$DB" 'CREATE INDEX IF NOT EXISTS idx_note_author_fp ON note(author_fp);'
  else
    warn "No encontré DB $DB; omitida migración"
  fi
else
  warn "sqlite3 no instalado; no puedo verificar esquema"
fi

##############################################################################
# 5) Reinicio local + pruebas de endpoints
##############################################################################
say "Reiniciando servidor local"
: > "$LOG" || true
: > "$HOOKLOG" || true
export RATELIMIT_STORAGE_URI="${RATELIMIT_STORAGE_URI:-memory://}"
pkill -f "python .*run.py" 2>/dev/null || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 25 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || true)"
[ -z "${PORT:-}" ] && PORT=8000
echo "PORT detectado: $PORT" >>"$out"

say "Smoke tests locales"
for U in "/healthz" "/api/notes?page=1"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT$U" || true)
  echo "GET $U -> $code" >>"$out"
done

code_post=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"text":"diag","hours":24}' "http://127.0.0.1:$PORT/api/notes" || true)
echo "POST /api/notes -> $code_post" >>"$out"

say "Tail de logs locales"
tail -n 30 "$LOG" >>"$out" 2>&1 || true
say "Tail de hook logs"
tail -n 30 "$HOOKLOG" >>"$out" 2>&1 || true

##############################################################################
# 6) Commit & push (para redeploy en Render)
##############################################################################
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "chore(doctor): fix routes indent + create_note alias + author_fp hook & DB + PORT binding + limiter default" || true
  git push -u --force-with-lease origin "$BRANCH" || warn "Push falló (revisa remoto/credenciales)."
fi

say "Reporte guardado en $out"
