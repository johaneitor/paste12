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

def line_no(pos): return s.count('\n', 0, pos) + 1

def find_next_def(start):
    m = re.search(r'(?ms)^\s*def\s+([A-Za-z_]\w*)\s*\(', s[start:])
    if not m: return None, None
    def_pos = start + m.start()
    name = m.group(1)
    return name, def_pos

def find_paren_close(start_paren):
    depth = 0
    i = start_paren
    while i < len(s):
        ch = s[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None

def insert_before(pos, text):
    return s[:pos] + text + s[pos:]

# --- 1) Añadir endpoint= a TODOS los decoradores @X.route(...) sin endpoint= (soporta multilínea)
i = 0
while True:
    m = re.search(r'(?ms)^[ \t]*@[A-Za-z_]\w*\.route\(', s[i:])
    if not m: break
    start = i + m.start()
    # buscar '(' que abre los args de route
    paren = s.find('(', start)
    if paren == -1: i = start + 1; continue
    end = find_paren_close(paren)
    if end is None: i = paren + 1; continue

    deco_text = s[start:end+1]
    # si ya tiene endpoint=, skip
    if re.search(r'endpoint\s*=', deco_text):
        i = end + 1
        continue

    # buscar la def asociada (saltando decoradores consecutivos)
    scan = end + 1
    while True:
        # saltar líneas en blanco y otros decoradores
        m2 = re.match(r'(?ms)^\s*@', s[scan:])
        if m2:
            # hay otro decorador; movemos scan al final de ese decorador (balanceamos paréntesis)
            d2 = scan + m2.start()
            paren2 = s.find('(', d2)
            if paren2 == -1:
                scan = d2 + 1
                continue
            end2 = find_paren_close(paren2)
            if end2 is None:
                scan = paren2 + 1
                continue
            scan = end2 + 1
            continue
        break

    fname, def_pos = find_next_def(scan)
    if not fname:
        # fallback si no encontramos def
        fname = "handler"
        def_pos = start

    ep = f'{fname}__L{line_no(def_pos)}'
    # Inserción justo antes del ')' final del decorador
    s = insert_before(end, f', endpoint="{ep}"')
    i = end + len(f', endpoint="{ep}"') + 1

# --- 2) Añadir endpoint= a TODOS los .add_url_rule(... ) sin endpoint= (soporta multilínea)
i = 0
while True:
    m = re.search(r'(?ms)\b[A-Za-z_]\w*\.add_url_rule\s*\(', s[i:])
    if not m: break
    start = i + m.start()
    paren = s.find('(', start)
    if paren == -1:
        i = start + 1; continue
    end = find_paren_close(paren)
    if end is None:
        i = paren + 1; continue
    call = s[start:end+1]
    if re.search(r'endpoint\s*=', call):
        i = end + 1; continue
    mv = re.search(r'view_func\s*=\s*([A-Za-z_]\w*)', call)
    vf = mv.group(1) if mv else 'handler'
    ep = f'{vf}__AURL__L{line_no(start)}'
    s = insert_before(end, f', endpoint="{ep}"')
    i = end + len(f', endpoint="{ep}"') + 1

# Limpieza de saltos extra
s = re.sub(r'\n{3,}', '\n\n', s)

open(p, 'w', encoding='utf-8').write(s)
print("[OK] Endpoints fijados en decoradores multilínea y add_url_rule multilínea.")
PY

# Reiniciar y probar rápido
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 120 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"probe-mline","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
