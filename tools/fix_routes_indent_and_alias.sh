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
import io,sys,re
path=sys.argv[1]
s=open(path,'r',encoding='utf-8').read()
lines=s.splitlines(True)

# 1) Normalizar/Arreglar la llamada Note(...) más cercana a la línea ~137
target_line=137
# Encontrar todas las posiciones de "Note("
starts=[m.start() for m in re.finditer(r'\bNote\s*\(', s)]
if starts:
    # Elegimos la más cercana a la posición de la línea 137
    # Convertimos línea->offset
    off_line=0
    line_no=1
    for i,ch in enumerate(s):
        if line_no>=target_line: 
            off_line=i; break
        if ch=='\n': line_no+=1
    if off_line==0: off_line=len(s)
    start=min(starts, key=lambda x: abs(x-off_line))

    # Emparejar paréntesis
    i=start
    depth=0
    while i<len(s):
        if s[i]=='(':
            depth+=1
        elif s[i]==')':
            depth-=1
            if depth==0:
                end=i
                break
        i+=1
    else:
        end=None
    if end is not None:
        call = s[start:end]  # sin el ')' final
        # Remover duplicados/variantes de author_fp
        call_no_author = re.sub(r'\s*author_fp\s*=\s*client_fingerprint\(\)\s*,?', '', call)
        # Calcular indent
        line_start = s.rfind('\n', 0, start)+1
        indent = re.match(r'[ \t]*', s[line_start:start]).group(0) + '    '
        # Asegurar coma al final si hace falta
        body = call_no_author.rstrip()
        if not re.search(r',\s*$', body):
            body += ','
        # Insertar author_fp al final
        body = body + '\n' + indent + 'author_fp=client_fingerprint(),'
        new_call = body
        s = s[:start] + new_call + s[end:]  # mantiene el ')' que ya estaba en s[end]
# 2) Quitar líneas duplicadas sueltas con author_fp=client_fingerprint(), fuera de la llamada
s = re.sub(r'(\n[ \t]*author_fp\s*=\s*client_fingerprint\(\)\s*,\s*\n){2,}', r'\1', s)

# 3) Agregar alias de ruta para POST /api/notes si existe create_note
# Buscamos la definición
m = re.search(r'^\s*def\s+create_note\s*\(', s, flags=re.M)
if m:
    # Buscar el decorador inmediatamente encima
    deco_block_start = s.rfind('\n', 0, m.start())+1
    block = s[deco_block_start:m.start()]
    deco = None
    for line in block.strip().splitlines():
        if line.strip().startswith('@') and '.route(' in line:
            deco = line.strip()
            break
    if deco:
        # @X.route('...', methods=[...])
        p = re.match(r'@(\w+)\.route\((.*)\)', deco)
        if p:
            prefix, args = p.group(1), p.group(2)
            # Si ya hay alias /api/notes, no hacemos nada
            if '/api/notes' not in s:
                alias = f'@{prefix}.route("/api/notes", methods=["POST"])'
                s = s[:deco_block_start] + alias + '\n' + s[deco_block_start:]
open(path,'w',encoding='utf-8').write(s)
print("[OK] routes.py parcheado")
PY

# 4) Reinicio local (si estás en Termux corriendo run.py)
if [ -f "$RUNPY" ]; then
  echo "[+] Reiniciando server local (nohup)…"
  : > "$LOG" || true
  pkill -f "python .*run.py" 2>/dev/null || true
  nohup python "$RUNPY" >"$LOG" 2>&1 &
  sleep 2
  tail -n 20 "$LOG" || true
fi

# 5) Commit & push (para que Render redeploye)
if [ -d .git ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD || echo main)"
  git add -A
  git commit -m "fix(routes): normalize Note(...) + add POST /api/notes alias" || true
  git push -u --force-with-lease origin "$BRANCH" || echo "[!] Push falló (revisa remoto/credenciales)."
else
  echo "[i] No es un repo git; omito push."
fi

echo "[✓] Listo."
