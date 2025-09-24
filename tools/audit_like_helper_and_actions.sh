#!/usr/bin/env bash
set -euo pipefail
f="wsgiapp/__init__.py"
[ -f "$f" ] || { echo "no existe $f"; exit 2; }

echo "== TABS (deben ser 0) =="
if grep -nP '\t' "$f" >/dev/null; then
  echo "✗ Tabs detectados. Normalizar a espacios."
else
  echo "✓ sin tabs"
fi
echo

echo "== Duplicados de def _json_passthrough_like =="
grep -nE '^[[:space:]]*def +_json_passthrough_like\>' "$f" || echo "(ninguno)"
echo

echo "== Ventana 300-480 =="
nl -ba "$f" | sed -n '300,480p'
echo

echo "== POST /api/notes/:id/* signature =="
grep -nE 'if +path\.startswith\("/api/notes/"\) +and +method +== +"POST"' "$f" || echo "(POST block no detectado)"
grep -nE 'if +path\.startswith\("/api/notes/"\) +and +method +== +"GET"' "$f"  || echo "(GET block no detectado)"
echo

echo "== Compilación =="
python - <<'PY'
import py_compile, sys
try:
    py_compile.compile("wsgiapp/__init__.py", doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    # pista de contexto
    try:
        import traceback; traceback.print_exc()
    except: pass
    sys.exit(1)
PY
