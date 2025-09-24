#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
SHIM="$ROOT/contract_shim.py"
WSGI="$ROOT/wsgi.py"

echo "== Fix import/render (contract_shim.application) =="

if [[ ! -f "$SHIM" ]]; then
  echo "⚠ No existe contract_shim.py — nada que hacer."
  exit 0
fi

# A) Asegurar que contract_shim exporte 'application'
if ! grep -qE '^\s*application\s*=' "$SHIM"; then
  if grep -qE '^\s*app\s*=' "$SHIM"; then
    echo "→ Agregando 'application = app' al final de contract_shim.py"
    printf "\n# export para gunicorn\napplication = app\n" >> "$SHIM"
  else
    echo "⚠ No se encontró 'app =' ni 'application =' en contract_shim.py (revisar manualmente)."
  fi
fi

# B) Asegurar que wsgi.py importe correctamente
if [[ -f "$WSGI" ]]; then
  if grep -q "from contract_shim import application" "$WSGI"; then
    echo "→ wsgi.py ya importa 'application' desde contract_shim"
  elif grep -q "from contract_shim import app as application" "$WSGI"; then
    echo "→ wsgi.py ya importa 'app as application' (ok)"
  else
    echo "→ Ajustando import en wsgi.py"
    # Intenta reemplazar import existente; si no hay, inserta al inicio
    if grep -q "from contract_shim import" "$WSGI"; then
      sed -i "s|from contract_shim import .*|from contract_shim import application  # export canonical|g" "$WSGI"
    else
      sed -i "1s|^|from contract_shim import application  # export canonical\n|" "$WSGI"
    fi
  fi
else
  echo "⚠ No existe wsgi.py — omito paso B."
fi

python - <<'PY'
import py_compile, sys
for f in ("contract_shim.py","wsgi.py"):
    try:
        py_compile.compile(f, doraise=True)
        print(f"✓ py_compile {f}")
    except Exception as e:
        print(f"FAIL py_compile {f}: {e}")
        sys.exit(1)
PY

echo "Listo."
