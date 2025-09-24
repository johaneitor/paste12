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

# Detectar nombre del blueprint con nombre lógico "api"
m_bp = re.search(r'(?m)^\s*([A-Za-z_]\w*)\s*=\s*Blueprint\(\s*[\'"]api[\'"]\s*,', s)
bp = m_bp.group(1) if m_bp else "bp"

def deco(line): return line if line.endswith("\n") else line+"\n"

def block_range_for_func(name:str):
    m = re.search(r'(?m)^([ \t]*)def\s+'+re.escape(name)+r'\s*\(', s)
    if not m: return None
    start_def = m.start()
    i = s.rfind('\n',0,start_def) + 1
    deco_start = i
    while True:
        prev = s.rfind('\n',0,deco_start-1)
        if prev < 0: break
        line = s[prev+1:deco_start-1]
        if line.strip().startswith('@'):
            deco_start = prev+1; continue
        break
    return (deco_start, start_def)

def replace_decorators(name:str, new_decos:list[str]):
    global s
    rng = block_range_for_func(name)
    if not rng: return
    a,b = rng
    s = s[:a] + "".join(deco(d) for d in new_decos) + s[a:]

def purge_wrong_notes_routes():
    """Quita decoradores de /api/notes o /notes en funciones que NO sean list_notes/create_note."""
    global s
    lines=s.splitlines(True)
    out=[]; i=0
    while i<len(lines):
        ln=lines[i]
        if re.match(r'^\s*@[A-Za-z_]\w*\.route\(', ln):
            blk=[]; j=i
            while j<len(lines) and lines[j].lstrip().startswith('@'):
                blk.append(j); j+=1
            fname=None
            if j<len(lines):
                mdef=re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[j])
                if mdef: fname=mdef.group(1)
            keep=set(blk)
            for k in blk:
                t=lines[k].replace('"',"'")
                if ("'/api/notes'" in t or "'/notes'" in t):
                    if fname not in ("list_notes","create_note"):
                        keep.discard(k)
            for k in blk:
                out.append(lines[k] if k in keep else "# FIX-REMOVED wrong notes mapping\n")
            if j<len(lines):
                out.append(lines[j]); i=j+1; continue
            i=j; continue
        out.append(ln); i+=1
    s=''.join(out)

def replace_like_report_view():
    """Deja like/report/view SOLO con /notes/<int:note_id>/* (POST)."""
    global s
    for name, tail in [
        ("like_note","like"),
        ("report_note","report"),
        ("view_note","view"),
    ]:
        rng=block_range_for_func(name)
        if not rng: continue
        a,b = rng
        # eliminar decoradores actuales del bloque
        s = s[:a] + s[b:]
        s = s[:a] + deco(f"@{bp}.route('/notes/<int:note_id>/{tail}', methods=['POST'], endpoint='{name}')") + s[a:]

def comment_wrong_add_url_rule():
    """Comenta add_url_rule de ( /api/notes | /notes ) que no apunten a list_notes/create_note con view_func."""
    global s
    def find_close(text, start):
        depth=0
        for i in range(start,len(text)):
            c=text[i]
            if c=='(':
                depth+=1
            elif c==')':
                depth-=1
                if depth==0: return i
        return None
    i=0
    while True:
        m=re.search(r'(?ms)\b[A-Za-z_]\w*\.add_url_rule\s*\(', s[i:])
        if not m: break
        start=i+m.start()
        openp = s.find('(', start)
        endp = find_close(s, openp) or (openp+1)
        call = s[start:endp+1]
        callq = call.replace('"',"'")
        if ("'/api/notes'" in callq or "'/notes'" in callq):
            ok = re.search(r"view_func\s*=\s*(create_note|list_notes)\b", call) is not None
            if not ok:
                s = s[:start] + "# FIX-REMOVED wrong add_url_rule for notes\n" + s[endp+1:]
                i = start+1; continue
        i = endp+1

# 1) Purga mapeos erróneos y add_url_rule conflictivos
purge_wrong_notes_routes()
comment_wrong_add_url_rule()

# 2) Normaliza list_notes y create_note a rutas RELATIVAS (se aplicará url_prefix del blueprint)
replace_decorators("list_notes",  [f"@{bp}.route('/notes', methods=['GET'], endpoint='list_notes')"])
replace_decorators("create_note", [f"@{bp}.route('/notes', methods=['POST'], endpoint='create_note')"])

# 3) Aísla like/report/view SOLO con /notes/<int:note_id>/*
replace_like_report_view()

# 4) Sustitución masiva en decoradores restantes: '/api/notes' -> '/notes' (evita /api/api/notes)
s = re.sub(r"(@\s*"+re.escape(bp)+r"\.route\(\s*['\"])\/api\/notes", r"\1/notes", s)

# 5) Quitar espacios en blanco sobrantes
s = re.sub(r'\n{3,}', '\n\n', s)

open(p,'w',encoding='utf-8').write(s)
print("[OK] routes.py: prefijos normalizados y rutas de notes saneadas (/notes → url_prefix '/api').")
PY

# Reiniciar y validar URL MAP + smokes
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
print()
print("EXPECT: /api/notes GET api.list_notes | /api/notes POST api.create_note | /api/notes/<int:note_id>/like POST api.like_note")
PY

echo "[+] Smoke GET /api/notes"
curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
echo
echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" -d '{"text":"fix-v2-ok","hours":24}' "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
echo
