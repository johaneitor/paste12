#!/usr/bin/env bash
set -euo pipefail
F="contract_shim.py"
[[ -f "$F" ]] || { echo "ℹ️  No existe $F, nada que corregir."; exit 0; }

TS="$(date +%Y%m%d-%H%M%SZ)"
cp -f "$F" "$F.bak.$TS"

# 1) Quitar salidas en import (sys.exit / raise SystemExit) si estuvieran al nivel superior
sed -i 's/^\s*raise\s\+SystemExit.*$/# [guarded] eliminado raise SystemExit en import/g' "$F" || true
sed -i 's/^\s*sys\.exit\s*(.*)$/# [guarded] eliminado sys.exit en import/g' "$F" || true

# 2) Asegurar bloque main seguro
if ! grep -q '^if __name__ == .__main__.:$' "$F"; then
  printf '\nif __name__ == "__main__":\n    pass\n' >> "$F"
fi

python -m py_compile "$F" && echo "✓ py_compile $F"
