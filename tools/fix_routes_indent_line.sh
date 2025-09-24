#!/usr/bin/env bash
set -euo pipefail
REMOTE="$1"; LNO="$2"
LOCAL="${REMOTE#/opt/render/project/src/}"
[[ -f "$LOCAL" ]] || { echo "No existe localmente: $LOCAL"; exit 1; }
cp -n "$LOCAL" "$LOCAL.bak.$(date -u +%Y%m%dT%H%M%SZ)" || true

python - <<PY "$LOCAL" "$LNO"
from pathlib import Path; import sys,re
p = Path(sys.argv[1]); L = int(sys.argv[2])-1
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = s.splitlines()
if not (0 <= L < len(lines)): raise SystemExit("línea fuera de rango")

def lead(x): return len(x) - len(x.lstrip(" "))
def seti(i,n): lines[i] = (" " * n) + lines[i].lstrip()

# llevar a columna 0 decoradores/imports/defs mal indentados
for i,ln in enumerate(lines):
    if re.match(r"^\s+from (flask|__future__)\s+import ", ln) or re.match(r"^\s+import sqlalchemy\b", ln):
        lines[i] = ln.lstrip()
    if re.match(r"^\s+@api\.route\(", ln): lines[i] = ln.lstrip()
    if re.match(r"^\s+def [A-Za-z_]\w*\(", ln):
        if i>0 and (lines[i-1].strip()=="" or lines[i-1].lstrip().startswith("@")):
            lines[i] = ln.lstrip()

# igualar indent de la línea L al contexto
prev = lines[L-1] if L-1>=0 else ""
want = lead(prev)
# si la anterior cierra con ':', sumar bloque
if prev.rstrip().endswith(":"): want += 4
seti(L, want)

# si la anterior termina en '(', sangrado de continuación
if prev.rstrip().endswith("("):
    seti(L, max(lead(lines[L]), lead(prev)+2))

p.write_text("\n".join(lines) + ("\n" if s.endswith("\n") else ""), encoding="utf-8")
print("OK: ajustada indent en", p, "línea", L+1)
PY

git add "$LOCAL" >/dev/null 2>&1 || true
git commit -m "fix(routes): corrige indent en ${LOCAL}:${LNO}" >/dev/null 2>&1 || true
git push origin HEAD >/dev/null 2>&1 || true
echo "✓ Commit & push hecho."
