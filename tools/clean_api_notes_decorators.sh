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
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()
lines=s.splitlines(True)

# Detectar nombre del blueprint (bp, api, etc.)
bp = None
m = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(', s)
if m: bp = m.group(1)
if not bp:
    m = re.search(r'(?m)^\s*@([A-Za-z_]\w*)\.route\(', s)
    if m and m.group(1) != 'app': bp = m.group(1)
if not bp:
    bp = 'bp'  # fallback razonable
    print(f"[i] No detecté Blueprint explícito; asumo '{bp}'.")

def is_decorator_for_api_notes(i):
    line = lines[i]
    return re.match(rf'^\s*@{bp}\.route\(\s*[\'\"]/api/notes[\'\"]\s*,\s*methods\s*=\s*\[', line) is not None

def next_def_name(i):
    j = i + 1
    # saltar otros decoradores seguidos
    while j < len(lines) and lines[j].lstrip().startswith('@'):
        j += 1
    if j < len(lines):
        m = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[j])
        if m: return m.group(1), j
    return None, j

# 1) Quitar decoradores /api/notes que no estén sobre create_note (POST) o list_notes (GET)
to_delete = []
for i in range(len(lines)):
    if is_decorator_for_api_notes(i):
        fname, j = next_def_name(i)
        if fname not in ('create_note','list_notes'):
            # borrar SOLO este decorador
            to_delete.append(i)

for i in reversed(to_delete):
    del lines[i]

s2 = ''.join(lines)

# 2) Asegurar que list_notes tenga decorador GET correcto y create_note tenga POST
def ensure_decorator(func_name, methods):
    global s2
    # localizar def
    m = re.search(rf'(?m)^(\s*)def\s+{func_name}\s*\(', s2)
    if not m:
        print(f"[!] No encontré def {func_name}()")
        return
    indent = m.group(1)
    # buscar bloque de decoradores inmediatamente encima
    start = s2.rfind('\n', 0, m.start()) + 1
    deco_start = start
    while True:
        prev = s2.rfind('\n', 0, deco_start-1)
        if prev < 0: break
        line = s2[prev+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev+1
        else:
            break
    block = s2[deco_start:m.start()]
    want = f"@{bp}.route('/api/notes', methods={methods})"
    # ya está?
    if want in block:
        return
    # eliminar cualquier decorador /api/notes residual mal formado encima de esta función
    block = re.sub(rf'(?m)^\s*@{bp}\.route\(\s*[\'\"]/api/notes[\'\"].*$', '', block)
    # insertar el correcto al inicio del bloque de decoradores
    new_block = (want + "\n") + block
    s2 = s2[:deco_start] + new_block + s2[m.start():]

ensure_decorator('list_notes', "['GET']")
ensure_decorator('create_note', "['POST']")

# 3) Compactar líneas en blanco
s2 = re.sub(r'\n{3,}', '\n\n', s2)

open(p,'w',encoding='utf-8').write(s2)
print("[OK] Decoradores /api/notes saneados y vinculados al Blueprint correcto.")
PY

# Reinicio rápido y pruebas
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 60 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"probe-clean","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,80p'
echo
