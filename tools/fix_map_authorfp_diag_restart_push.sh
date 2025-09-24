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

[ -f "$RUNPY" ] || { warn "No encuentro $RUNPY"; exit 1; }
[ -f "$ROUTES" ] || { warn "No encuentro $ROUTES"; exit 1; }

mkdir -p backend/utils db/migrations public docs/snippets

# --- Hook con logging (safe) ---
say "Escribo hook before_insert (safe) con logging"
cat > "$HOOK" <<'PY'
import os, hashlib, datetime, traceback
from sqlalchemy import event
from flask import request, has_request_context

def _log(msg):
    try:
        with open("/tmp/author_fp_hook.log","a") as f:
            ts = datetime.datetime.now().isoformat(timespec="seconds")
            f.write(f"[{ts}] %s\n" % msg)
    except Exception:
        pass

Note = None
_errs = []
for modname in ("backend.models", "backend.models.note"):
    try:
        mod = __import__(modname, fromlist=["*"])
        cand = getattr(mod, "Note", None)
        if cand is not None:
            Note = cand
            break
    except Exception as e:
        _errs.append(f"{modname}: {e!r}")

if Note is None:
    _log("ERROR importando Note: " + " | ".join(_errs))
else:
    _log("OK import Note: " + repr(Note))

def _fp() -> str:
    if not has_request_context():
        return "noctx"
    ip = (request.headers.get("X-Forwarded-For", "")
          or request.headers.get("CF-Connecting-IP", "")
          or (request.remote_addr or ""))
    ua = request.headers.get("User-Agent", "")
    salt = os.environ.get("FP_SALT", "")
    return hashlib.sha256(f"{ip}|{ua}|{salt}".encode()).hexdigest()[:32]

if Note is not None:
    has_attr = hasattr(Note, "author_fp")
    _log("Note tiene atributo author_fp: %s" % has_attr)
    @event.listens_for(Note, "before_insert")
    def note_before_insert(mapper, connection, target):
        try:
            if not getattr(target, "author_fp", None):
                target.author_fp = _fp()
                _log("Set author_fp en before_insert")
            else:
                _log("author_fp ya venía seteado")
        except Exception as ex:
            _log("ERROR before_insert: " + repr(ex))
            _log(traceback.format_exc())
PY

# --- util fingerprint (para usar desde routes.py también) ---
if ! grep -q "client_fingerprint" backend/utils/fingerprint.py 2>/dev/null; then
  say "Creo backend/utils/fingerprint.py"
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

# --- Asegurar import del hook y limiter en run.py ---
if ! grep -q "backend\.models_hooks" "$RUNPY"; then
  say "Importo backend.models_hooks en run.py"
  awk 'NR==1{print "import backend.models_hooks  # registra hooks (author_fp)"; print; next} {print}' "$RUNPY" > "$RUNPY.tmp" && mv "$RUNPY.tmp" "$RUNPY"
fi
if ! grep -q "RATELIMIT_STORAGE_URI" "$RUNPY"; then
  say "Configuro RATELIMIT_STORAGE_URI (memory por defecto)"
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

# --- Inyectar author_fp=client_fingerprint() dentro de Note(...) (por si tu flujo no activa el hook) ---
if ! grep -q "from backend\.utils\.fingerprint import client_fingerprint" "$ROUTES"; then
  awk 'NR==1{print "from backend.utils.fingerprint import client_fingerprint"; print; next} {print}' "$ROUTES" > "$ROUTES.tmp" && mv "$ROUTES.tmp" "$ROUTES"
fi
if ! grep -q "author_fp=client_fingerprint()" "$ROUTES"; then
  say "Inyecto author_fp=client_fingerprint() en Note(...)"
  BAK="$ROUTES.bak.$(date +%s)"; cp "$ROUTES" "$BAK"
  awk '
    BEGIN{in_call=0; seen_author=0}
    {
      line=$0
      if (in_call==0 && line ~ /Note[[:space:]]*\(/) { in_call=1 }
      if (in_call==1 && line ~ /author_fp[[:space:]]*=/) { seen_author=1 }
      if (in_call==1 && line ~ /\)/) {
        if (seen_author==0) print "        author_fp=client_fingerprint(),"
        in_call=0; seen_author=0
      }
      print line
    }
  ' "$BAK" > "$ROUTES"
fi

# --- DIAG del modelo (sin usar truthiness) ---
say "DIAG: mapeo de Note y columnas"
python - <<'PY'
import importlib, sys
Note=None
for m in ("backend.models","backend.models.note"):
    try:
        mod=importlib.import_module(m)
        cls=getattr(mod,"Note",None)
        if cls is not None:
            Note=cls
            src=m
            break
    except Exception as e:
        print("DIAG: fallo import",m,":",e)
if Note is None:
    print("DIAG: No pude importar Note"); sys.exit(0)
print("DIAG: Note importado desde",src)
tbl=getattr(Note,"__table__",None)
if tbl is None:
    print("DIAG: Note no tiene __table__ (¿no es declarativo?)"); sys.exit(0)
cols=list(tbl.columns.keys())
print("DIAG: columnas Note =>", cols)
print("DIAG: author_fp en columnas:", "author_fp" in cols)
print("DIAG: hasattr(Note,'author_fp'):", hasattr(Note,"author_fp"))
PY

# --- Si falta el atributo en la CLASE, insertarlo en el archivo de modelo ---
say "Busco dónde está definida class Note"
NOTE_FILE="$(grep -R --include='*.py' -n 'class[[:space:]]\+Note' backend | head -n1 | cut -d: -f1 || true)"
if [ -n "${NOTE_FILE:-}" ] && ! grep -q "author_fp" "$NOTE_FILE"; then
  say "Parcheo $NOTE_FILE para agregar author_fp al modelo"
  python - "$NOTE_FILE" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()
m=re.search(r'(?m)^class\s+Note\s*\([^)]*\):\s*\n',s)
if not m:
    print("DIAG: No encuentro class Note"); sys.exit(0)
start=m.end()
m2=re.search(r'(?m)^([ \t]+)\S',s[start:])
indent=m2.group(1) if m2 else '    '
m3=re.search(r'(?m)^%sdef\s' % re.escape(indent), s[start:])
ins_at = (m3.start()+start) if m3 else len(s)
line = f"{indent}author_fp = db.Column(db.String(64), nullable=False, index=True)\n"
open(p,'w',encoding='utf-8').write(s[:ins_at]+line+s[ins_at:])
print("DIAG: Insertado campo author_fp en class Note")
PY
else
  say "El modelo ya parece declarar author_fp o no ubiqué class Note"
fi

# --- Reinicio server y muestro logs ---
say "Reinicio server con nohup (log en $LOG)"
: > "$LOG" || true
: > "$HOOKLOG" || true
export RATELIMIT_STORAGE_URI="${RATELIMIT_STORAGE_URI:-memory://}"
pkill -f "python .*run.py" 2>/dev/null || true
nohup env RATELIMIT_STORAGE_URI="$RATELIMIT_STORAGE_URI" python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || true)"
[ -z "${PORT:-}" ] && PORT=8000

say "Tail de $LOG"
tail -n 20 "$LOG" || true
say "Puerto detectado: $PORT"

# --- Probar POST en varios endpoints comunes ---
DATA='{"text":"probe-from-fix-map"}'
for U in "/note" "/notes" "/api/note" "/api/notes"; do
  say "POST http://127.0.0.1:$PORT$U"
  curl -s -X POST -H "Content-Type: application/json" -d "$DATA" "http://127.0.0.1:$PORT$U" || true
  echo
done

say "author_fp_hook.log (si corrió el hook, lo verás aquí)"
tail -n 30 "$HOOKLOG" || true

say "paste12.log (errores recientes)"
tail -n 50 "$LOG" || true

# --- Push ---
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix: map author_fp in Note; add before_insert hook; limiter default; safe diagnostics" || true
  git push -u --force-with-lease origin "$BRANCH" || warn "Push falló (revisa remoto/credenciales)."
else
  warn "No es un repo git; omito push."
fi

say "Hecho."
