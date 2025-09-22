#!/usr/bin/env bash
set -euo pipefail

echo "== harden_sqlalchemy_pool_v3 =="

CANDS=(wsgi.py backend/__init__.py backend/app.py app.py wsgiapp/__init__.py)
target=""
for f in "${CANDS[@]}"; do
  [[ -f "$f" ]] || continue
  if grep -qE 'from flask|Flask\(|SQLAlchemy' "$f"; then target="$f"; break; fi
done

if [[ -z "$target" ]]; then
  echo "ERROR: no encontré archivo Flask/wsgi para inyectar."
  exit 1
fi
echo "→ archivo objetivo: $target"
cp -f "$target" "$target.bak.$(date +%s)"

P12_TARGET="$target" python - <<'PY'
import os,re,sys
p = os.environ['P12_TARGET']
src = open(p,'r',encoding='utf-8').read()

if 'pool_pre_ping' in src and 'SQLALCHEMY_ENGINE_OPTIONS' in src:
    print("✓ engine options ya detectadas. No cambio.")
    sys.exit(0)

helper = r"""
# === Paste12 DB hardening (auto-inyectado) ===
def __p12_apply_db_hardening(app):
    import os
    app.config.setdefault('SQLALCHEMY_TRACK_MODIFICATIONS', False)
    opts = app.config.setdefault('SQLALCHEMY_ENGINE_OPTIONS', {})
    opts.setdefault('pool_pre_ping', True)
    opts.setdefault('pool_recycle', int(os.environ.get('SQL_POOL_RECYCLE','280')))
    opts.setdefault('pool_size',    int(os.environ.get('SQL_POOL_SIZE','5')))
    opts.setdefault('max_overflow', int(os.environ.get('SQL_MAX_OVERFLOW','5')))
    ca = opts.setdefault('connect_args', {})
    ca.setdefault('sslmode', os.environ.get('PGSSLMODE','require'))
    ca['keepalives'] = 1
    ca['keepalives_idle'] = int(os.environ.get('PGKEEPALIVES_IDLE','45'))
    ca['keepalives_interval'] = int(os.environ.get('PGKEEPALIVES_INTERVAL','10'))
    ca['keepalives_count'] = int(os.environ.get('PGKEEPALIVES_COUNT','3'))
# === /Paste12 DB hardening ===
""".lstrip()

if '__p12_apply_db_hardening' not in src:
    # Inserto helper al final
    src = src.rstrip() + "\n\n" + helper

changed = False

# Caso A: app = Flask(...) a nivel módulo
m = re.search(r'^\s*app\s*=\s*Flask\([^\n]*\)\s*$', src, re.M)
if m:
    inspt = m.end()
    after = src[inspt:inspt+200]
    if '__p12_apply_db_hardening(app)' not in after:
        src = src[:inspt] + "\n__p12_apply_db_hardening(app)\n" + src[inspt:]
        changed = True

# Caso B: factory def create_app(...)
if not changed:
    fac = re.search(r'^\s*def\s+create_app\s*\([^)]*\)\s*:\s*', src, re.M)
    if fac:
        # buscar el 'app = Flask(' más cercano después
        inner = src[fac.end():]
        m2 = re.search(r'^\s*app\s*=\s*Flask\([^\n]*\)\s*$', inner, re.M)
        if m2:
            st = fac.end() + m2.end()
            # ¿ya está la llamada?
            tail = src[st:st+200]
            if '__p12_apply_db_hardening(app)' not in tail:
                src = src[:st] + "\n    __p12_apply_db_hardening(app)\n" + src[st:]
                changed = True

# Caso C: plan de reserva — si existe 'app' en globals al import
if not changed and 'if "app" in globals()' not in src:
    src = src.rstrip() + """

# Fallback: aplicar al importar si existe 'app' global
try:
    if "app" in globals():
        __p12_apply_db_hardening(app)
except Exception:
    pass
"""

open(p,'w',encoding='utf-8').write(src)
print("✓ hardening aplicado (o verificado).")
PY

python - <<'PY'
import os,py_compile
print("✓ py_compile", py_compile.compile(os.environ.get('P12_TARGET','wsgi.py'), doraise=False))
PY

echo "Listo."
