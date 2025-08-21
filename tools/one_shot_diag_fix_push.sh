#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
cd "$ROOT_DIR"

say(){ printf "\n[+] %s\n" "$*"; }
warn(){ printf "\n[!] %s\n" "$*"; }

RUNPY="run.py"
ROUTES="backend/routes.py"
HOOK="backend/models_hooks.py"
LOG="/tmp/paste12.log"
HOOKLOG="/tmp/author_fp_hook.log"

[ -f "$RUNPY" ] || { warn "No encuentro $RUNPY (ejecuta este script desde la raíz del repo)"; exit 1; }
[ -f "$ROUTES" ] || { warn "No encuentro $ROUTES"; exit 1; }

mkdir -p backend/utils tools db/migrations public docs/snippets

say "Escribo hook con logging (before_insert → author_fp)"
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

Note = None
err = None
try:
    from backend.models import Note as _Note  # type: ignore
    Note = _Note
except Exception as e:
    err = e
    try:
        from backend.models.note import Note as _Note  # type: ignore
        Note = _Note
    except Exception as e2:
        err = e2

if Note is None:
    _log("ERROR: No pude importar Note: " + (str(err) if err else "sin detalle"))
else:
    _log("OK: Importado Note=" + str(Note))

def _fp() -> str:
    if not has_request_context():
        return "noctx"
    ip = (
        request.headers.get("X-Forwarded-For", "")
        or request.headers.get("CF-Connecting-IP", "")
        or (request.remote_addr or "")
    )
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

if Note is not None:
    if not hasattr(Note, "author_fp"):
        _log("ADVERTENCIA: El modelo Note NO tiene atributo 'author_fp'. El ORM no lo insertará.")
    else:
        _log("OK: Note tiene atributo 'author_fp'")

    @event.listens_for(Note, "before_insert")
    def note_before_insert(mapper, connection, target):
        try:
            if not getattr(target, "author_fp", None):
                target.author_fp = _fp()
                _log("Set author_fp en before_insert")
            else:
                _log("author_fp ya presente en el objeto")
        except Exception as ex:
            _log("ERROR en before_insert: " + repr(ex))
            _log(traceback.format_exc())
PY

# util fingerprint (para uso directo desde routes.py si hiciera falta)
if ! grep -q "client_fingerprint" backend/utils/fingerprint.py 2>/dev/null; then
  say "Escribo backend/utils/fingerprint.py"
  cat > backend/utils/fingerprint.py <<'PY'
import os, hashlib
from flask import request, has_request_context
def client_fingerprint() -> str:
    if not has_request_context(): return "noctx"
    ip = request.headers.get("X-Forwarded-For","") or request.headers.get("CF-Connecting-IP","") or (request.remote_addr or "")
    ua = request.headers.get("User-Agent",""); salt = os.environ.get("FP_SALT","")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]
PY
fi

# asegurar import del hook en run.py
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  say "Añado import backend.models_hooks en run.py"
  awk 'NR==1{print "import backend.models_hooks  # registra hooks (author_fp)"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
fi

# Config por defecto para Flask-Limiter (silencia warning si no hay Redis)
if ! grep -q "RATELIMIT_STORAGE_URI" "$RUNPY"; then
  say "Añado config RATELIMIT_STORAGE_URI a run.py"
  cat >> "$RUNPY" <<'PY'

# --- Config por defecto para Flask-Limiter ---
try:
    import os
    if "RATELIMIT_STORAGE_URI" not in getattr(app, "config", {}):
        app.config["RATELIMIT_STORAGE_URI"] = os.environ.get("RATELIMIT_STORAGE_URI", "memory://")
except Exception:
    pass
# --- Fin config Limiter ---
PY
fi

# Inyectar author_fp en Note(...) si tu handler no lo pone (idempotente)
if ! grep -q "from backend\.utils\.fingerprint import client_fingerprint" "$ROUTES"; then
  awk 'NR==1{print "from backend.utils.fingerprint import client_fingerprint"; print; next} {print}' "$ROUTES" > "$ROUTES.tmp" && mv "$ROUTES.tmp" "$ROUTES"
fi
if ! grep -q "author_fp=client_fingerprint()" "$ROUTES"; then
  say "Intento inyectar author_fp=client_fingerprint() dentro de Note(...)" 
  BAK="$ROUTES.bak.$(date +%s)"; cp "$ROUTES" "$BAK"
  awk '
    BEGIN{in_call=0; seen_author=0; patched=0}
    {
      line=$0
      if (in_call==0 && line ~ /Note[[:space:]]*\(/) { in_call=1 }
      if (in_call==1 && line ~ /author_fp[[:space:]]*=/) { seen_author=1 }
      if (in_call==1 && line ~ /\)/) {
        if (seen_author==0) { print "        author_fp=client_fingerprint(),"; patched=1 }
        in_call=0; seen_author=0
      }
      print line
    }
    END{ if (patched==0) {} }
  ' "$BAK" > "$ROUTES"
fi

# DIAGNÓSTICO de mapeo del modelo Note → ¿existe columna author_fp?
say "Diagnóstico del modelo Note (mapeo de columna)"
python - <<'PY'
import sys, importlib
mod = None; Note = None
paths = ["backend.models", "backend.models.note"]
for m in paths:
    try:
        mod = importlib.import_module(m)
        Note = getattr(mod, "Note", None)
        if Note: break
    except Exception:
        pass
if not Note:
    print("DIAG: No pude importar Note desde backend.models ni backend.models.note"); sys.exit(0)
tbl = getattr(Note, "__table__", None)
if not tbl:
    print("DIAG: Note no tiene __table__ (¿no es modelo SQLAlchemy?)"); sys.exit(0)
cols = [c.name for c in tbl.columns]
print("DIAG: columnas Note =>", cols)
print("DIAG: author_fp en columnas:", "author_fp" in cols)
print("DIAG: atributo mapeado 'author_fp' en clase:", hasattr(Note, "author_fp"))
PY

# Si el atributo NO está mapeado en el modelo, intentamos parchear el archivo de la clase
say "Buscando archivo que define class Note"
NOTE_FILE="$(grep -R --include='*.py' -n 'class[[:space:]]\+Note' backend | head -n1 | cut -d: -f1 || true)"
if [ -n "${NOTE_FILE:-}" ] && ! grep -q "author_fp" "$NOTE_FILE"; then
  say "Parcheando $NOTE_FILE para agregar campo author_fp en la clase Note"
  python - "$NOTE_FILE" <<'PY'
import sys,re,io,os
path=sys.argv[1]
s=open(path,'r',encoding='utf-8').read()

m=re.search(r'(?m)^class\s+Note\s*\([^)]*\):\s*\n',s)
if not m:
    print("DIAG: No encontré class Note para parchear"); sys.exit(0)
start=m.end()
m2=re.search(r'(?m)^([ \t]+)\S',s[start:])
indent=m2.group(1) if m2 else '    '
m3=re.search(r'(?m)^%sdef\s' % re.escape(indent), s[start:])
ins_at = m3.start()+start if m3 else len(s)
line = f"{indent}author_fp = db.Column(db.String(64), nullable=False, index=True)\n"
open(path,'w',encoding='utf-8').write(s[:ins_at] + line + s[ins_at:])
print("DIAG: Campo author_fp insertado en class Note")
PY
else
  say "El modelo ya parece tener author_fp o no ubico el archivo de Note"
fi

# Reinicio servidor con logs
say "Reiniciando servidor (nohup)…"
: > "$LOG" || true
: > "$HOOKLOG" || true
export RATELIMIT_STORAGE_URI="${RATELIMIT_STORAGE_URI:-memory://}"
pkill -f "python .*run.py" 2>/dev/null || true
nohup env RATELIMIT_STORAGE_URI="$RATELIMIT_STORAGE_URI" python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

# Detectar puerto desde el log (línea tipo: 'Servidor en http://127.0.0.1:8006')
PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || true)"
[ -z "${PORT:-}" ] && PORT=8000

say "Últimas líneas de $LOG"
tail -n 20 "$LOG" || true

say "Puerto detectado: $PORT"

# Endpoint candidato (probamos varios)
URLS=(
  "http://127.0.0.1:$PORT/note"
  "http://127.0.0.1:$PORT/notes"
  "http://127.0.0.1:$PORT/api/note"
  "http://127.0.0.1:$PORT/api/notes"
)
DATA='{"text":"probe-from-one-shot"}'

for U in "${URLS[@]}"; do
  say "POST $U"
  curl -s -X POST -H "Content-Type: application/json" -d "$DATA" "$U" || true
  echo
done

say "author_fp_hook.log (si el hook corrió, verás eventos)"
tail -n 30 "$HOOKLOG" || true

say "paste12.log (errores recientes)"
tail -n 50 "$LOG" || true

# Push
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix: map author_fp on Note + hook + limiter default + diagnostics" || true
  git push -u --force-with-lease origin "$BRANCH" || warn "Push falló (revisa remoto/credenciales)."
else
  warn "No es un repo git; omito push."
fi

say "Hecho."
