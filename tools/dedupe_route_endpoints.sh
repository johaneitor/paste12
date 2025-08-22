#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"
ROUTES="backend/routes.py"
RUNPY="run.py"
LOG=".tmp/paste12.log"

[ -f "$ROUTES" ] || { echo "[!] No encuentro $ROUTES"; exit 1; }

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys

p = sys.argv[1]
s = open(p, 'r', encoding='utf-8').read()

# Captura bloques tipo:
#   @bp.route('/x', methods=['GET'])
#   @bp.route('/y', methods=['POST'])
#   def func(...):
block_re = re.compile(r'(?ms)^([ \t]*(?:@[A-Za-z_]\w*\.route\([^\n]*\)\s*\n)+)([ \t]*def\s+([A-Za-z_]\w*)\s*\()', re.M)

# Encuentra TODOS los bloques decoradores + def
blocks = []
for m in block_re.finditer(s):
    deco_block = m.group(1)
    def_indent = m.group(2)
    func = m.group(3)
    blocks.append((m.start(1), m.end(1), m.start(2), m.end(2), deco_block, def_indent, func))

# Agrupar por nombre de función
by_func = {}
for b in blocks:
    by_func.setdefault(b[6], []).append(b)

# Reescritura: para cada función que aparece más de una vez, añadir endpoint="func__N" en TODOS sus decoradores del 2º en adelante si falta
offset = 0
s_list = list(s)

def patch_block(deco_block, func, occurrence_idx):
    # occurrence_idx empieza en 0 (la primera vez no tocamos endpoints)
    lines = deco_block.splitlines(True)
    if occurrence_idx == 0:
        return ''.join(lines)
    new_lines = []
    for ln in lines:
        if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', ln):
            if 'endpoint=' not in ln:
                # Insertar endpoint antes del paréntesis final ')'
                pos = ln.rfind(')')
                if pos >= 0:
                    ln = ln[:pos] + f', endpoint="{func}__{occurrence_idx+1}"' + ln[pos:]
                else:
                    # caso raro: sin ')', lo añadimos al final
                    ln = ln.rstrip() + f', endpoint="{func}__{occurrence_idx+1}")\n'
        new_lines.append(ln)
    return ''.join(new_lines)

# Construir nuevo texto con parches aplicados
out = []
last = 0
for func, occs in by_func.items():
    # mantener el orden en el archivo
    occs_sorted = sorted(occs, key=lambda x: x[0])
    for idx, (s1, e1, s2, e2, deco_block, def_indent, funcname) in enumerate(occs_sorted):
        out.append(s[last:s1])
        out.append(patch_block(deco_block, funcname, idx))
        last = e1
# añadir el resto
out.append(s[last:])
s2 = ''.join(out)

# Limpieza de saltos en blanco extra
s2 = re.sub(r'\n{3,}', '\n\n', s2)

open(p, 'w', encoding='utf-8').write(s2)
print("[OK] Endpoints deduplicados: se agregaron endpoint=\"<func>__N\" a decoradores repetidos.")
PY

# Reiniciar y probar
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 100 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"probe-dedupe","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,80p'
echo
