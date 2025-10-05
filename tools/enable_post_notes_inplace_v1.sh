#!/usr/bin/env bash
set -euo pipefail
PY="wsgiapp/__init__.py"
[[ -f "$PY" ]] || { echo "ERROR: falta $PY"; exit 1; }
cp -a "$PY" "${PY}.bak-$(date -u +%Y%m%d-%H%M%SZ)"
python - "$PY" <<'PY'
import io,sys,re
p=sys.argv[1]
s=io.open(p,"r",encoding="utf-8").read()
# Unificar el decorador de /api/notes para permitir POST/OPTIONS (y conservar GET)
s=re.sub(
    r'@app\.route\(\s*[\'"]/api/notes[\'"]\s*(?:,\s*methods\s*=\s*\[[^\]]*\])?\s*\)',
    '@app.route("/api/notes", methods=["GET","POST","OPTIONS"])',
    s, count=1, flags=re.M
)
io.open(p,"w",encoding="utf-8").write(s)
print("PATCH_OK",p)
PY
python -m py_compile "$PY"
echo "OK: $PY compilado"
