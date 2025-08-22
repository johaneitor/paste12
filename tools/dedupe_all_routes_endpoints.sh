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
src = open(p, 'r', encoding='utf-8').read()
lines = src.splitlines(True)

# --- 1) Mapa de lineas de 'def <name>(' para obtener la línea de la función
def_lines = {}
for i, ln in enumerate(lines, start=1):
    m = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', ln)
    if m:
        def_lines[m.group(1)] = i

# Helpers
def add_endpoint_to_decorator_line(line: str, endpoint: str) -> str:
    if 'endpoint=' in line:
        return line
    # insertar antes del ')' final
    pos = line.rfind(')')
    if pos >= 0:
        return line[:pos] + f', endpoint="{endpoint}"' + line[pos:]
    # fallback: agregar al final
    ll = line.rstrip()
    if ll.endswith(')'):
        return ll[:-1] + f', endpoint="{endpoint}")\n'
    return ll + f', endpoint="{endpoint}")\n'

# --- 2) Para cada bloque de decoradores @X.route(...) que precede a una def, agregar endpoint único si falta
i = 0
while i < len(lines):
    if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', lines[i]):
        deco_start = i
        deco_idxs = []
        while i < len(lines) and lines[i].lstrip().startswith('@'):
            if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', lines[i]):
                deco_idxs.append(i)
            i += 1
        # La siguiente línea debería ser la def
        if i < len(lines):
            m = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[i])
            if m:
                fname = m.group(1)
                fline = def_lines.get(fname, i+1)
                unique_endpoint = f'{fname}__L{fline}'
                # aplica a todos los decoradores del bloque que no tengan endpoint
                for di in deco_idxs:
                    lines[di] = add_endpoint_to_decorator_line(lines[di], unique_endpoint)
        continue
    i += 1

# --- 3) Para las llamadas <bp>.add_url_rule(...), agregar endpoint si falta (usando view_func si se puede)
# Trabajamos sobre el texto completo porque pueden ser llamadas en una sola línea
text = ''.join(lines)

def repl_add_url_rule(m):
    call = m.group(0)
    # si ya tiene endpoint=, no tocamos
    if re.search(r'endpoint\s*=', call):
        return call
    # intentar extraer view_func
    mv = re.search(r'view_func\s*=\s*([A-Za-z_]\w*)', call)
    if mv:
        vf = mv.group(1)
    else:
        vf = 'handler'
    # estimar número de línea del match para hacer el endpoint único
    start = m.start()
    line_no = text.count('\n', 0, start) + 1
    endpoint = f'{vf}__AURL__L{line_no}'
    # insertar antes del ')' final
    pos = call.rfind(')')
    if pos >= 0:
        return call[:pos] + f', endpoint="{endpoint}"' + call[pos:]
    return call.rstrip() + f', endpoint="{endpoint}")'

text = re.sub(r'(?ms)\b[A-Za-z_]\w*\.add_url_rule\([^)]*\)', repl_add_url_rule, text)

# Limpieza de saltos extra
text = re.sub(r'\n{3,}', '\n\n', text)

open(p, 'w', encoding='utf-8').write(text)
print("[OK] Endpoints únicos agregados a todos los @route/add_url_rule sin endpoint=")
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
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"probe-dedupe-all","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
