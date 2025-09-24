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
lines = s.splitlines(True)

# 1) Detectar TODOS los nombres de blueprint definidos
bp_defs = re.findall(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(', s)
if not bp_defs:
    # Si no se detecta ninguno, intentamos inferir desde decoradores existentes
    dec_bps = re.findall(r'(?m)^\s*@([A-Za-z_]\w*)\.route\(', s)
    if dec_bps:
        bp_defs = [dec_bps[0]]
    else:
        bp_defs = ['bp']  # fallback
bp_official = bp_defs[0]
bp_set = set(bp_defs)

# 2) Normalizar TODOS los decoradores a bp_official (por si hay @api, @bp, @API, etc.)
def repl_bp(m):
    return f"@{bp_official}.route("
s_norm = re.sub(r'(?m)^\s*@([A-Za-z_]\w*)\.route\(', repl_bp, s)

# 3) Mapear decoradores por función para detectar múltiples @route sobre la misma función
lines = s_norm.splitlines(True)
decor_groups = []  # lista de (idx_inicio_bloque, idx_def, func_name, indices_de_decoradores)
i = 0
while i < len(lines):
    line = lines[i]
    if re.match(r'^\s*@' + re.escape(bp_official) + r'\.route\(', line):
        # acumular todos los decoradores consecutivos
        deco_idx = []
        start = i
        while i < len(lines) and lines[i].lstrip().startswith('@'):
            if re.match(r'^\s*@' + re.escape(bp_official) + r'\.route\(', lines[i]):
                deco_idx.append(i)
            i += 1
        # Buscar la def inmediatamente siguiente
        if i < len(lines):
            m = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[i])
            if m:
                func = m.group(1)
                decor_groups.append((start, i, func, deco_idx))
        continue
    i += 1

# 4) Para cada función con múltiples decoradores, agregar endpoint="func__N" si falta
for start, def_i, func, deco_idx in decor_groups:
    if len(deco_idx) <= 1:
        continue
    # Asegurar endpoint único en todos
    for k, di in enumerate(deco_idx, start=1):
        line = lines[di]
        # Si ya tiene endpoint=..., lo dejamos; si no, lo agregamos antes del ')'
        if 'endpoint=' in line:
            continue
        # Insertar antes del ')' final del decorador
        # Soportar casos con parámetros previos (methods=..., etc.)
        # Nota: trabajamos por línea (decoradores comunes caben en una línea)
        pos = line.rfind(')')
        if pos == -1:
            # fallback tosco: agregar al final
            new_line = line.rstrip()[:-1] + f', endpoint="{func}__{k}")\n' if line.rstrip().endswith(')') \
                       else line.rstrip() + f', endpoint="{func}__{k}")\n'
        else:
            new_line = line[:pos] + f', endpoint="{func}__{k}"' + line[pos:]
        lines[di] = new_line

s_fixed = ''.join(lines)

# 5) Limpieza de espacios en blanco
s_fixed = re.sub(r'\n{3,}', '\n\n', s_fixed)

open(p, 'w', encoding='utf-8').write(s_fixed)
print(f"[OK] Blueprint oficial: {bp_official}. Decoradores normalizados y endpoints únicos cuando hay múltiples @route sobre la misma función.")
PY

# Reiniciar y probar
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2
tail -n 80 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "--- GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,40p'
echo
echo "--- POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"probe-dups","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,80p'
echo
