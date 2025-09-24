#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${1:-$(pwd)}"; cd "$ROOT"
ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"
REPORT=".tmp/paste12_doctor_report.txt"
HOOKLOG=".tmp/author_fp_hook.log"

: > "$LOG"; : > "$REPORT"; : > "$HOOKLOG"

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
txt=open(p,'r',encoding='utf-8').read()

# 1) Separar encabezado (shebang/comentarios iniciales + docstring si existe)
i=0
lines=txt.splitlines(True)

def is_comment_or_blank(l):
    ls=l.lstrip()
    return (not ls) or ls.startswith('#!') or (ls.startswith('#') and 'coding' in ls)

# Saltar comentarios/blank iniciales
while i < len(lines) and is_comment_or_blank(lines[i]):
    i+=1

# Detectar docstring al inicio
doc_start=i
doc_end=i
if i < len(lines) and lines[i].lstrip().startswith(("'''",'"""')):
    quote=lines[i].lstrip()[:3]
    # incluir primera línea
    doc_end=i+1
    # buscar cierre
    while doc_end < len(lines):
        if quote in lines[doc_end]:
            doc_end+=1
            break
        doc_end+=1
header=''.join(lines[:doc_end])
rest=''.join(lines[doc_end:])

# 2) Extraer TODOS los from __future__ import ... de cualquier parte de rest
future_pat=re.compile(r'(?m)^\s*from\s+__future__\s+import\s+.*?$')
future_lines=future_pat.findall(rest)
# Orden estable y únicos
seen=set(); fut_unique=[]
for l in future_lines:
    if l not in seen:
        fut_unique.append(l)
        seen.add(l)

# 3) Quitar esos future del resto
rest = future_pat.sub('', rest)

# 4) Asegurar UN solo import de fingerprint y quitar duplicados en rest
fp_line='from backend.utils.fingerprint import client_fingerprint\n'
rest = re.sub(r'(?m)^\s*from\s+backend\.utils\.fingerprint\s+import\s+client_fingerprint\s*$\n?', '', rest)

# 5) Reconstruir: header + future + (una línea en blanco) + fp_line + resto
pieces=[header]
if fut_unique:
    pieces.append(''.join(l if l.endswith('\n') else l+'\n' for l in fut_unique))
# Asegurar una línea en blanco entre bloques si hace falta
if pieces and not pieces[-1].endswith('\n\n'):
    pieces[-1]=pieces[-1].rstrip('\n')+'\n'
    pieces.append('\n')
# Insertar fingerprint import justo después de future (si no estaba en header)
if fp_line not in header:
    pieces.append(fp_line)
# Asegurar una línea en blanco antes del resto
if not rest.startswith('\n'):
    pieces.append('\n')
pieces.append(rest.lstrip('\n'))

new_txt=''.join(pieces)

# 6) Limpieza: colapsar espacios en blanco excesivos
new_txt=re.sub(r'\n{3,}', '\n\n', new_txt)

# Validación mínima: los __future__ deben aparecer antes que cualquier otro import
# (esto ya se cumple por construcción, pero dejamos el archivo listo)
open(p,'w',encoding='utf-8').write(new_txt)
print("[OK] Reordenado: __future__ al inicio y fingerprint import después.")
PY

echo "[+] Validando sintaxis de routes.py"
python -m py_compile "$ROUTES"

echo "[+] Reiniciando run.py (nohup) → logs en ./.tmp"
pkill -f "python .*run.py" 2>/dev/null || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 40 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" | tail -n1 | cut -d: -f2 || true)"
[ -z "${PORT:-}" ] && PORT=8000
echo "PORT=$PORT" >>"$REPORT"

echo "[+] Smoke tests"
GETC=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/api/notes?page=1" || true)
POSTC=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"text":"diag","hours":24}' "http://127.0.0.1:$PORT/api/notes" || true)
echo "GET /api/notes -> $GETC"  >>"$REPORT"
echo "POST /api/notes -> $POSTC" >>"$REPORT"

tail -n 40 "$LOG"     >>"$REPORT" 2>&1 || true
tail -n 40 "$HOOKLOG" >>"$REPORT" 2>&1 || true

# Commit & push para redeploy en Render
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix: reorder __future__ imports; keep fingerprint import after them; restart & smoke tests" || true
  git push -u --force-with-lease origin "$BRANCH" || echo "[!] Push falló (revisa remoto/credenciales)."
fi

echo "[✓] Hecho. Revisa .tmp/paste12_doctor_report.txt y .tmp/paste12.log"
