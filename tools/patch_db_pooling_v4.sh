#!/usr/bin/env bash
set -euo pipefail
TARGET="backend/__init__.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${TARGET}.${TS}.bak"
cp -f "$TARGET" "$BAK"
echo "[pooling] Backup: $BAK"

python - <<'PY'
import io, re, sys, os
p = "backend/__init__.py"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def ensure_imports(s):
    need = []
    if not re.search(r'\bos\b', s): need.append("import os")
    if not re.search(r'\bre\b', s): need.append("import re")
    if need:
        # inserta después del primer import existente o al principio
        m = re.search(r'^(from .+|import .+)$', s, re.M)
        if m:
            s = s[:m.end()] + "\n" + "\n".join(need) + s[m.end():]
        else:
            s = "\n".join(need) + "\n" + s
    return s

def ensure_normalize_block(s):
    block = r"""
# == paste12: normalize DATABASE_URL ==
def _normalize_db_url(url: str) -> str:
    if not url: return url
    # postgres:// -> postgresql+psycopg2://
    if url.startswith("postgres://"):
        return "postgresql+psycopg2://" + url[len("postgres://"):]
    return url

try:
    _env_url = os.environ.get("DATABASE_URL", "") or os.environ.get("DB_URL", "")
    _norm_url = _normalize_db_url(_env_url)
    if _norm_url and _norm_url != _env_url:
        os.environ["DATABASE_URL"] = _norm_url
except Exception:
    pass
# == end normalize ==
""".strip("\n")
    if "normalize DATABASE_URL" not in s:
        # Colocar después de imports
        m = re.search(r'^(?:from .+|import .+)(?:\n(?:from .+|import .+))*', s, re.M)
        if m:
            s = s[:m.end()] + "\n\n" + block + "\n\n" + s[m.end():]
        else:
            s = block + "\n\n" + s
    return s

def ensure_engine_options(s):
    # Si ya hay SQLALCHEMY_ENGINE_OPTIONS, lo reemplazamos suavemente
    opts_re = re.compile(r'(?m)^\s*app\.config\[\s*[\'"]SQLALCHEMY_ENGINE_OPTIONS[\'"]\s*\]\s*=\s*\{.*?\}', re.S)
    new_opts = """app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
    "pool_pre_ping": True,
    "pool_recycle": 180,
    "pool_timeout": 15,
    "pool_size": 5,
    "max_overflow": 10,
})"""
    if opts_re.search(s):
        s = opts_re.sub(new_opts, s)
    else:
        # Insertar cerca de la configuración SQLAlchemy
        anchor = re.search(r'(?m)^\s*app\.config\[[\'"]SQLALCHEMY_DATABASE_URI[\'"]\]\s*=\s*.+$', s)
        if anchor:
            idx = anchor.end()
            s = s[:idx] + "\n" + new_opts + "\n" + s[idx:]
        else:
            # Como fallback, búsquese la creación de app
            anchor = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
            if anchor:
                # colocar unas líneas después
                ins_at = s.find("\n", anchor.end())+1
                s = s[:ins_at] + new_opts + "\n" + s[ins_at:]
            else:
                # último recurso: al final
                s = s.rstrip() + "\n\n" + new_opts + "\n"

    return s

def ensure_db_uri(s):
    # Si no hay SQLALCHEMY_DATABASE_URI, ponemos uno por defecto (no pisa si ya existe)
    if re.search(r'SQLALCHEMY_DATABASE_URI', s): 
        return s
    stub = """# paste12: default DB URI if missing
app.config.setdefault("SQLALCHEMY_DATABASE_URI", os.environ.get("DATABASE_URL", "sqlite:///local.db"))
"""
    # Inserta tras creación de app
    m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
    if m:
        ins_at = s.find("\n", m.end())+1
        s = s[:ins_at] + stub + s[ins_at:]
    else:
        s = s.rstrip() + "\n\n" + stub
    return s

s = ensure_imports(s)
s = ensure_normalize_block(s)
s = ensure_db_uri(s)
s = ensure_engine_options(s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("[pooling] backend/__init__.py actualizado")
else:
    print("[pooling] Nada que cambiar (ya estaba)")
PY

python -m py_compile backend/__init__.py && echo "[pooling] py_compile OK"
echo "Listo. Despliega y probamos."
