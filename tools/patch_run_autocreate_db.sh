#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

RUNPY="run.py"
[ -f "$RUNPY" ] || { echo "[!] No encuentro $RUNPY"; exit 1; }

echo "[+] Backup de run.py"
cp "$RUNPY" "$RUNPY.bak.$(date +%s)"

python - "$RUNPY" <<'PY'
import io,sys,re
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# Ya existe el bloque? (evitamos duplicar)
if "db.create_all()" in s and "Auto create DB (idempotente)" in s:
    print("[i] Bloque de autocreate ya presente; nada que hacer.")
    sys.exit(0)

block = r"""
# --- Auto create DB (idempotente) ---
try:
    from backend import db
    with app.app_context():
        db.create_all()
        # Nota: create_all es segura (no pisa tablas existentes).
        print("~ Auto create DB: OK")
except Exception as _e:
    try:
        print("~ Auto create DB falló:", _e)
    except Exception:
        pass
# --- Fin auto create DB ---
"""

# Inserción: justo después de la primera definición/instanciación de app
m = re.search(r'(?m)^(.*app\s*=\s*.+)$', s)
if m:
    idx = m.end()
    s = s[:idx] + "\n" + block + s[idx:]
else:
    # Si no encontramos, lo agregamos al final (mejor que nada)
    s = s.rstrip()+"\n"+block+"\n"

open(p,'w',encoding='utf-8').write(s)
print("[OK] Insertado bloque de Auto create DB en run.py")
PY
