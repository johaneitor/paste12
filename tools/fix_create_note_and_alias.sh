#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"
cd "$ROOT"

ROUTES="backend/routes.py"
RUNPY="run.py"
LOG="/tmp/paste12.log"

[ -f "$ROUTES" ] || { echo "[!] No encuentro $ROUTES"; exit 1; }

echo "[+] Backup de routes.py"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)"

python - "$ROUTES" <<'PY'
import re, sys
path=sys.argv[1]
s=open(path,'r',encoding='utf-8').read()

# 0) Asegurar import del fingerprint util
if "from backend.utils.fingerprint import client_fingerprint" not in s:
    s = "from backend.utils.fingerprint import client_fingerprint\n" + s

# 1) Limpiar lineas sueltas/duplicadas mal indentadas de author_fp
s = re.sub(r'(?m)^\s*author_fp\s*=\s*client_fingerprint\(\)\s*,?\s*$', '', s)

# 2) Localizar la definición de create_note y su decorador
m_def = re.search(r'(?m)^([ \t]*)def\s+create_note\s*\(', s)
if not m_def:
    print("[!] No encontré def create_note(...). Aborto modificaciones limpias.", file=sys.stderr)
    open(path,'w',encoding='utf-8').write(s)
    sys.exit(0)

indent = m_def.group(1)
# Buscar decoradores inmediatamente encima
decor_start = s.rfind("\n", 0, m_def.start()) + 1
decor_block_start = decor_start
while True:
    prev_nl = s.rfind("\n", 0, decor_block_start-1)
    line = s[prev_nl+1:decor_block_start-1]
    if line.strip().startswith("@"):
        decor_block_start = prev_nl+1
    else:
        break
decor_block = s[decor_block_start:m_def.start()]
# Detectar el prefijo del blueprint: @<bp>.route(...)
bp_match = re.search(r'@([A-Za-z_][A-Za-z0-9_]*)\.route\(', decor_block)
bp = bp_match.group(1) if bp_match else "app"  # fallback

# 3) Encontrar el final de la función (siguiente def o decorador al mismo nivel)
pos = m_def.end()
end = len(s)
while True:
    m_next = re.search(r'(?m)^(%s(?:def\s+|@))' % re.escape(indent), s[pos:])
    if not m_next:
        break
    end = pos + m_next.start()
    break

# 4) Construir nueva función limpia
new_func = f'''{decor_block}@{bp}.route("/api/notes", methods=["POST"])
{indent}def create_note():
{indent}    from flask import request, jsonify
{indent}    from datetime import timedelta
{indent}    try:
{indent}        data = request.get_json(silent=True) or {{}}
{indent}    except Exception:
{indent}        data = {{}}
{indent}    text = (data.get("text") or "").strip()
{indent}    if not text:
{indent}        return jsonify({{"error": "text required"}}), 400
{indent}    try:
{indent}        hours = int(data.get("hours", 24))
{indent}    except Exception:
{indent}        hours = 24
{indent}    hours = min(168, max(1, hours))
{indent}    now = _now()  # usa tu helper existente
{indent}    n = Note(
{indent}        text=text,
{indent}        timestamp=now,
{indent}        expires_at=now + timedelta(hours=hours),
{indent}        author_fp=client_fingerprint(),
{indent}    )
{indent}    db.session.add(n)
{indent}    db.session.commit()
{indent}    return jsonify(_note_json(n, now)), 201
'''

# 5) Reemplazar bloque completo de la función por la versión limpia
s_fixed = s[:decor_block_start] + new_func + s[end:]

# 6) En las llamadas a Note(...) fuera de create_note, NO tocar.

open(path,'w',encoding='utf-8').write(s_fixed)
print("[OK] create_note reemplazado y alias POST /api/notes agregado; líneas sueltas de author_fp limpiadas.")
PY

# 3) Reinicio local (si existe run.py)
if [ -f "$RUNPY" ]; then
  echo "[+] Reiniciando server local (nohup)…"
  : > "$LOG" || true
  pkill -f "python .*run.py" 2>/dev/null || true
  nohup python "$RUNPY" >"$LOG" 2>&1 &
  sleep 2
  tail -n 25 "$LOG" || true
fi

# 4) Commit & push para que Render redeploye
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix(create_note): normaliza Note(...)+author_fp y añade alias POST /api/notes; limpia indentaciones" || true
  git push -u --force-with-lease origin "$BRANCH" || echo "[!] Push falló (revisa remoto/credenciales)."
else
  echo "[i] No es un repo git; omito push."
fi

echo "[✓] Listo. Verifica que ya no aparezca 'unexpected indent' y que POST /api/notes devuelva 201."
