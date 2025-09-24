#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

touch_changed=0

patch_file() {
  local F="$1"
  [ -f "$F" ] || return 0
  echo "[+] Parchando $F"
  python - "$F" <<'PY'
import re, sys, io, os, textwrap
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

def ensure_helper_block(txt):
    if "_normalize_database_url(" in txt and "apply_engine_hardening(" in txt:
        return txt
    helper = r"""
# --- DB hardening helpers (idempotente) ---
def _normalize_database_url(url: str|None):
    if not url:
        return url
    # Corrige postgres:// -> postgresql://
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]
    # Asegura sslmode=require si no está presente
    if "sslmode=" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}sslmode=require"
    return url

def apply_engine_hardening(app):
    # Motor con pre_ping y recycle para evitar EOF/idle disconnects
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {})
    opts = app.config["SQLALCHEMY_ENGINE_OPTIONS"]
    opts.setdefault("pool_pre_ping", True)
    opts.setdefault("pool_recycle", 300)
    opts.setdefault("pool_size", 5)
    opts.setdefault("max_overflow", 10)
    opts.setdefault("pool_timeout", 30)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = opts
"""
    return txt + "\n" + textwrap.dedent(helper)

def insert_normalization(txt):
    # Busca alguna asignación de SQLALCHEMY_DATABASE_URI o lectura de env
    if "SQLALCHEMY_DATABASE_URI" in txt and "_normalize_database_url(" in txt:
        return txt
    # Inserta un bloque seguro después del primer config.update o creación de app
    pat = r"(app\.config\[\"SQLALCHEMY_DATABASE_URI\"\]\s*=\s*.*)"
    if re.search(pat, txt):
        def repl(m):
            line = m.group(1)
            extra = (
                line + "\n" +
                "app.config[\"SQLALCHEMY_DATABASE_URI\"] = _normalize_database_url(app.config[\"SQLALCHEMY_DATABASE_URI\"])"
            )
            return extra
        return re.sub(pat, repl, txt, count=1)

    # Si no hay asignación directa, intenta agregar tras detección de app = Flask(...)
    pat2 = r"(app\s*=\s*Flask\(.*?\)\s*\n)"
    if re.search(pat2, txt, flags=re.S):
        def repl2(m):
            base = m.group(1)
            extra = (
                base +
                "app.config[\"SQLALCHEMY_DATABASE_URI\"] = _normalize_database_url(\n"
                "    app.config.get(\"SQLALCHEMY_DATABASE_URI\", os.environ.get(\"DATABASE_URL\"))\n"
                ")\n"
            )
            return extra
        return re.sub(pat2, repl2, txt, count=1, flags=re.S)
    return txt

def ensure_apply_engine(txt):
    if "apply_engine_hardening(app)" in txt:
        return txt
    # Intenta insertar cerca de donde ya se inicializa la DB
    anchor_patterns = [
        r"(db\s*=\s*SQLAlchemy\(app\))",
        r"(db\.init_app\(app\))",
    ]
    for pat in anchor_patterns:
        if re.search(pat, txt):
            return re.sub(pat, r"\1\napply_engine_hardening(app)", txt, count=1)
    # Si no, intenta colocarlo tras la creación de app
    pat2 = r"(app\s*=\s*Flask\(.*?\)\s*\n)"
    if re.search(pat2, txt, flags=re.S):
        return re.sub(pat2, r"\1apply_engine_hardening(app)\n", txt, count=1, flags=re.S)
    return txt

def ensure_retry_create_all(txt):
    if "def _retry_create_all" in txt:
        return txt
    helper = r"""
# create_all con retry para evitar fallos transitorios de red/SSL
def _retry_create_all(db, app, tries=5):
    import time
    for i in range(tries):
        try:
            with app.app_context():
                db.create_all()
            return True
        except Exception as e:
            # backoff simple
            time.sleep(1 + i)
    return False
"""
    txt += "\n" + helper
    # Inserta una llamada al final donde ya suele haber un create_all()
    if "db.create_all()" in txt and "_retry_create_all(" not in txt:
        txt = txt.replace("db.create_all()", "_retry_create_all(db, app)")
    else:
        # como fallback: colócalo al final del archivo
        txt += "\ntry:\n    _retry_create_all(db, app)\nexcept Exception:\n    pass\n"
    return txt

orig = s
s = ensure_helper_block(s)
s = insert_normalization(s)
s = ensure_apply_engine(s)
s = ensure_retry_create_all(s)

if s != orig:
    open(p,'w',encoding='utf-8').write(s)
    print("[OK] actualizado", p)
else:
    print("[i] sin cambios", p)
PY
  touch_changed=1
}

# Intenta parchear en los lugares típicos
for f in backend/__init__.py render_entry.py wsgi.py; do
  [ -f "$f" ] && patch_file "$f"
done

# Commit & push si hubo cambios
if [ $touch_changed -eq 1 ]; then
  echo "[+] Commit & push"
  git add -A
  git commit -m "chore(db): harden SQLAlchemy (sslmode=require, pre_ping, pool_recycle, retry create_all)" || true
  git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"
else
  echo "[i] Nada para commitear"
fi

cat <<'NEXT'

[•] Hecho. Ahora:
1) Espera el redeploy de Render.
2) Verifica:
   APP="https://paste12-rmsk.onrender.com"
   curl -s "$APP/api/diag/import" | jq .
   curl -s "$APP/api/notes/diag" | jq .
3) Prueba interacciones:
   ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id')
   curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
   curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
   curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'

Si aún aparece 'SSL SYSCALL error: EOF detected', revisa en Render:
- Que la env var DATABASE_URL exista y apunte a Postgres.
- Si tu DATABASE_URL no trae ?sslmode=..., este parche lo añade.
- Reinicia manualmente el servicio por las dudas.

NEXT
