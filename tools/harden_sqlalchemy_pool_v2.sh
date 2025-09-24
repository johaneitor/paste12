#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

echo "== harden_sqlalchemy_pool_v2 =="

# Candidatos típicos donde vive la app Flask
CANDS=(wsgi.py backend/__init__.py backend/app.py app.py wsgiapp/__init__.py)

target=""
for f in "${CANDS[@]}"; do
  [[ -f "$f" ]] || continue
  # Heurística: que mencione Flask o SQLAlchemy
  if grep -qE 'from flask|Flask\(|SQLAlchemy' "$f"; then
    target="$f"; break
  fi
done

if [[ -z "$target" ]]; then
  echo "ERROR: no encontré archivo para inyectar config (wsgi/app)."
  exit 1
fi

echo "→ archivo objetivo: $target"

bak="$target.bak.$(date +%s)"
cp -f "$target" "$bak"

python - <<'PY'
import io,os,re,sys
path = os.environ.get('P12_TARGET')
with open(path,'r',encoding='utf-8') as fh:
    src = fh.read()

if 'SQLALCHEMY_ENGINE_OPTIONS' in src and 'pool_pre_ping' in src:
    print("✓ engine options ya presentes (pool_pre_ping detectado). No cambio.")
    sys.exit(0)

need_import_os = ('import os' not in src)

# Buscar la línea de creación de app Flask
m = re.search(r'^\s*app\s*=\s*Flask\([^)]*\)\s*$', src, re.M)
insert_after = m.end() if m else None

block = """
# === Paste12 DB hardening ===
{osimp}
app.config.setdefault('SQLALCHEMY_TRACK_MODIFICATIONS', False)
app.config.setdefault('SQLALCHEMY_ENGINE_OPTIONS', {})
__p12_opts = app.config['SQLALCHEMY_ENGINE_OPTIONS']
__p12_opts.setdefault('pool_pre_ping', True)
# recicla conexiones para evitar EOF/SSL mac y conexiones viejas
__p12_opts.setdefault('pool_recycle', int(os.environ.get('SQL_POOL_RECYCLE','280')))
__p12_opts.setdefault('pool_size',    int(os.environ.get('SQL_POOL_SIZE','5')))
__p12_opts.setdefault('max_overflow', int(os.environ.get('SQL_MAX_OVERFLOW','5')))
__p12_opts.setdefault('connect_args', {})
__p12_ca = __p12_opts['connect_args']
# ssl/keepalives; Render suele traer sslmode=require en la URL, igual reforzamos
__p12_ca.setdefault('sslmode', os.environ.get('PGSSLMODE','require'))
__p12_ca['keepalives'] = 1
__p12_ca['keepalives_idle'] = int(os.environ.get('PGKEEPALIVES_IDLE','45'))
__p12_ca['keepalives_interval'] = int(os.environ.get('PGKEEPALIVES_INTERVAL','10'))
__p12_ca['keepalives_count'] = int(os.environ.get('PGKEEPALIVES_COUNT','3'))
# === /Paste12 DB hardening ===
""".lstrip().format(osimp=("import os" if need_import_os else ""))

if insert_after is None:
    # Si no hay "app = Flask(...)" lo pegamos al inicio, es seguro
    out = block + "\n" + src
else:
    out = src[:insert_after] + "\n" + block + src[insert_after:]

with open(path,'w',encoding='utf-8') as fh:
    fh.write(out)

print("✓ engine options inyectadas.")
PY
P12_TARGET="$target" python - <<'PY'
# sanity compile
import py_compile, os
py_compile.compile(os.environ['P12_TARGET'], doraise=True)
print("✓ py_compile OK")
PY

echo "Listo."
