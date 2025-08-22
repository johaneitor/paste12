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

# Detectar nombre del blueprint que usa "api" como nombre lógico
m_bp = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(\s*[\'"]api[\'"]\s*,', s)
bp = m_bp.group(1) if m_bp else "bp"

def deco(line):  # helper para construir decoradores canónicos
    return line if line.endswith("\n") else line+"\n"

def block_range_for_func(name:str):
    """Devuelve (start_decorators, def_line_index) donde start_decorators es
    el inicio del bloque de decoradores inmediatamente encima del def name."""
    m = re.search(r'(?m)^([ \t]*)def\s+'+re.escape(name)+r'\s*\(', s)
    if not m: return None
    start_def = m.start()
    # subir líneas hasta que dejen de ser decoradores
    i = s.rfind('\n',0,start_def) + 1
    deco_start = i
    while True:
        prev = s.rfind('\n',0,deco_start-1)
        if prev < 0: break
        line = s[prev+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev+1
            continue
        break
    return (deco_start, start_def)

def replace_decorators(name:str, new_deco_lines:list[str]):
    global s
    rng = block_range_for_func(name)
    if not rng: return
    a,b = rng
    # Reemplazar bloque de decoradores por los provistos + el resto sin tocar
    s = s[:a] + "".join([deco(x) for x in new_deco_lines]) + s[a:]

def purge_wrong_api_notes():
    """Quita decoradores y add_url_rule de /api/notes en funciones que no sean list_notes/create_note."""
    global s
    lines = s.splitlines(True)
    out=[]; i=0
    while i<len(lines):
        ln = lines[i]
        if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', ln):
            # capturar bloque de decoradores
            dek_idx=[]; j=i
            while j<len(lines) and lines[j].lstrip().startswith('@'):
                dek_idx.append(j); j+=1
            # función destino
            fname=None
            if j<len(lines):
                mdef=re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[j])
                if mdef: fname=mdef.group(1)
            # filtrar decoradores erróneos
            keep=set(dek_idx)
            for k in dek_idx:
                t = lines[k]
                if "/api/notes" in t.replace('"',"'"):
                    if fname not in ("list_notes","create_note"):
                        keep.discard(k)
            for k in dek_idx:
                if k in keep:
                    out.append(lines[k])
                else:
                    out.append("# FIX-REMOVED wrong /api/notes mapping\n")
            if j<len(lines):
                out.append(lines[j]); i=j+1; continue
            i=j; continue
        out.append(ln); i+=1
    s=''.join(out)

def comment_wrong_add_url_rule():
    """Comenta add_url_rule('/api/notes', ...) que no apunte a create_note/list_notes."""
    global s
    def find_paren_close(text, start):
        depth=0
        i=start
        while i<len(text):
            if text[i]=='(':
                depth+=1
            elif text[i]==')':
                depth-=1
                if depth==0: return i
            i+=1
        return None
    i=0
    while True:
        m=re.search(r'(?ms)\b'+re.escape(bp)+r'\.add_url_rule\s*\(', s[i:])
        if not m: break
        start=i+m.start()
        openp = s.find('(', start)
        endp = find_paren_close(s, openp) or (openp+1)
        call = s[start:endp+1]
        if "/api/notes" in call.replace('"',"'"):
            ok = re.search(r"view_func\s*=\s*(create_note|list_notes)\b", call) is not None
            if not ok:
                s = s[:start] + "# FIX-REMOVED wrong add_url_rule for /api/notes\n" + s[endp+1:]
                i = start+1; continue
        i = endp+1

# 1) Purgar rutas erróneas de /api/notes
purge_wrong_api_notes()
comment_wrong_add_url_rule()

# 2) Normalizar decoradores de list_notes y create_note
replace_decorators("list_notes", [f"@{bp}.route('/api/notes', methods=['GET'], endpoint='list_notes')"])
replace_decorators("create_note", [f"@{bp}.route('/api/notes', methods=['POST'], endpoint='create_note')"])

# 3) Asegurar que like_note SOLO tenga /api/notes/<int:note_id>/like (POST)
rng = block_range_for_func("like_note")
if rng:
    a,b = rng
    # eliminar todos los decoradores existentes sobre like_note
    s = s[:a] + s[b:]
    # reinyectar el decorador correcto
    s = s[:a] + deco(f"@{bp}.route('/api/notes/<int:note_id>/like', methods=['POST'], endpoint='like_note')") + s[a:]

# 4) Compactar saltos de línea vacíos
s = re.sub(r'\n{3,}', '\n\n', s)

open(p,'w',encoding='utf-8').write(s)
print("[OK] routes.py saneado: GET/POST /api/notes correctos y like_note aislado.")
PY

# Reiniciar y verificar
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] Tail log:"
tail -n 120 "$LOG" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] URL MAP runtime:"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
rules=[(str(r),sorted([m for m in r.methods if m not in("HEAD","OPTIONS")]),r.endpoint) for r in app.url_map.iter_rules()]
for rule,methods,ep in sorted(rules): print(f"{rule:35s}  {','.join(methods):10s}  {ep}")
has_get=any(r for r in rules if r[0]=="/api/notes" and "GET" in r[1])
has_post=any(r for r in rules if r[0]=="/api/notes" and "POST" in r[1])
print(f"\n/api/notes GET:{has_get} POST:{has_post}")
PY

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"route-surgery-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
