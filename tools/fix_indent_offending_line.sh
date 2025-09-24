#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"

fix_once() {
  local tmp="/tmp/__err.json"
  local code
  code="$(curl -sS -o "$tmp" -w '%{http_code}' "$BASE/__api_import_error" || true)"
  echo "-- __api_import_error status: $code --"
  if [[ "$code" == "404" ]]; then
    echo "OK: no hay error de import"; return 0
  fi
  [[ "$code" == "200" ]] || { echo "Respuesta no JSON (status=$code)"; return 2; }

  read -r REMOTE LNO <<<"$(python - <<'PY' < "$tmp"
import sys,json,re
j=json.load(sys.stdin)
tb=j.get("traceback","")
m=re.search(r'File "([^"]+)", line (\d+)', tb)
print((m.group(1)+" "+m.group(2)) if m else "")
PY
)"
  [[ -n "${REMOTE:-}" && -n "${LNO:-}" ]] || { echo "No pude parsear archivo/línea"; return 2; }

  LOCAL="${REMOTE#/opt/render/project/src/}"
  [[ -f "$LOCAL" ]] || { echo "No existe localmente: $LOCAL (REMOTE=$REMOTE)"; return 2; }
  echo "→ Corrigiendo $LOCAL línea $LNO"

  cp -n "$LOCAL" "$LOCAL.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true
  python - "$LOCAL" "$LNO" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1]); L=int(sys.argv[2])-1
src=p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines=src.splitlines()
def lead(s): return len(s)-len(s.lstrip(" "))
def seti(i,n): lines[i]=(" "*n)+lines[i].lstrip()
# normalizar imports/decoradores a col 0
for i,ln in enumerate(lines):
    if re.match(r"^\s+from (flask|__future__)\s+import ", ln): lines[i]=ln.lstrip()
    if re.match(r"^\s+import (sqlalchemy|typing|datetime|re|json)\b", ln): lines[i]=ln.lstrip()
    if re.match(r"^\s+@api\.", ln): lines[i]=ln.lstrip()
# ajustar línea conflictiva
if 0 <= L < len(lines):
    prev = lines[L-1] if L-1>=0 else ""
    want = 8 if prev.rstrip().endswith(":") else 4
    if prev.rstrip().endswith("("):
        want = max(want, lead(prev)+2)
    seti(L, want)
# defs tras decorador/blanco a col 0
for i in range(1,len(lines)):
    if lines[i].lstrip().startswith("def ") and (lines[i-1].strip()=="" or lines[i-1].lstrip().startswith("@")):
        if lead(lines[i])>0: lines[i]=lines[i].lstrip()
p.write_text("\n".join(lines)+("\n" if src.endswith("\n") else ""), encoding="utf-8")
print("OK: escrito")
PY

  git add "$LOCAL" >/dev/null 2>&1 || true
  git commit -m "fix(routes): normaliza indentación en $LOCAL (auto a partir de __api_import_error)" >/dev/null 2>&1 || true
  git push origin HEAD >/dev/null 2>&1 || true

  local re
  re="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/__api_import_error" || true)"
  if [[ "$re" == "404" ]]; then
    echo "OK: __api_import_error=404"; return 0
  else
    echo "Aún falla (status=$re)"; return 3
  fi
}

echo "== fix_indent_offending_line @ $BASE =="
for i in 1 2 3 4 5; do
  echo "-- iteración $i --"
  if fix_once; then exit 0; fi
done
echo "No se pudo dejar __api_import_error en 404 tras 5 iteraciones."
exit 1
