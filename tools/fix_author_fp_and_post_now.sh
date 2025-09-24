#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

RUNPY="run.py"
ROUTES="backend/routes.py"
LOG=".tmp/paste12.log"

echo "[+] Backups"
cp "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

# --- 1) Localizar la clase Note real e inyectar author_fp en el MODELO si falta ---
python - <<'PY'
import importlib, inspect, io, re, sys, os
Note=None; src=None
err=[]
for modname in ("backend.models","backend.models.note"):
    try:
        mod=importlib.import_module(modname)
        cand=getattr(mod,"Note",None)
        if cand is not None:
            Note=cand; src=modname; break
    except Exception as e:
        err.append(f"{modname}: {e!r}")
if Note is None:
    print("[!] No pude importar Note:", " | ".join(err)); sys.exit(0)
try:
    path = inspect.getsourcefile(Note)
except Exception:
    path = None
print(f"[i] Note importada desde {src}, archivo={path}")
if not path or not os.path.isfile(path):
    print("[!] No pude resolver el archivo del modelo; omito parche de modelo.")
    sys.exit(0)

s=open(path,'r',encoding='utf-8').read()
if "author_fp" in s:
    print("[*] El modelo ya menciona author_fp (no toco).")
else:
    m=re.search(r'(?m)^class\s+Note\s*\([^)]*\):\s*\n', s)
    if not m:
        print("[!] No encontré la definición de class Note en", path)
    else:
        start=m.end()
        m2=re.search(r'(?m)^([ \t]+)\S', s[start:])
        indent=m2.group(1) if m2 else '    '
        # Insertar justo antes del primer método/attr al mismo nivel
        m3=re.search(r'(?m)^%s(def|@|[A-Za-z_])' % re.escape(indent), s[start:])
        at = (m3.start()+start) if m3 else len(s)
        line = f"{indent}author_fp = db.Column(db.String(64), nullable=False, index=True)\n"
        s2 = s[:at] + line + s[at:]
        open(path,'w',encoding='utf-8').write(s2)
        print(f"[OK] Insertado author_fp en {path}")

PY

# --- 2) Asegurar import del fingerprint util y pasar author_fp en el constructor dentro de create_note() ---
python - "$ROUTES" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()
if "from backend.utils.fingerprint import client_fingerprint" not in s:
    s = "from backend.utils.fingerprint import client_fingerprint\n" + s

# Normalizar la función create_note: garantizar que Note(... author_fp=client_fingerprint(), ...)
m=re.search(r'(?m)^([ \t]*)def\s+create_note\s*\(\)\s*:\s*\n', s)
if m:
    indent=m.group(1)
    pos=m.end()
    m_next=re.search(r'(?m)^(%s(?:def|@))' % re.escape(indent), s[pos:])
    end = pos + m_next.start() if m_next else len(s)
    func = s[m.start():end]

    # Parchear la llamada a Note(…)
    def patch_call(block):
        i=0; out=[]
        while True:
            m2=re.search(r'\bNote\s*\(', block[i:])
            if not m2:
                out.append(block[i:]); break
            st=i+m2.start()
            out.append(block[i:st])
            # balancear paréntesis
            j=st; depth=0
            while j<len(block):
                if block[j]=='(':
                    depth+=1
                elif block[j]==')':
                    depth-=1
                    if depth==0: break
                j+=1
            call = block[st:j]  # sin ')'
            body = call
            if "author_fp" not in call:
                # indent actual
                ls = block.rfind('\n', 0, st) + 1
                indent_call = re.match(r'[ \t]*', block[ls:st]).group(0) + '    '
                if not re.search(r',\s*$', body.strip()):
                    body = body.rstrip() + ','
                body = f"{body}\n{indent_call}author_fp=client_fingerprint(),"
            out.append(body)
            out.append(block[j]) # ')'
            i=j+1
        return ''.join(out)

    func2 = patch_call(func)
    s = s[:m.start()] + func2 + s[end:]
    open(p,'w',encoding='utf-8').write(s)
    print("[OK] create_note ahora pasa author_fp en el constructor.")
else:
    print("[!] No encontré def create_note() — no modificado.")
PY

# --- 3) Reiniciar y smokes ---
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
nohup python "$RUNPY" >"$LOG" 2>&1 &
sleep 2

echo "[+] URL MAP (notas):"
python - <<'PY'
import importlib
app=getattr(importlib.import_module("run"),"app",None)
for r in sorted(app.url_map.iter_rules(), key=lambda r: str(r)):
    if str(r).startswith("/api/notes"):
        ms=",".join(sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")]))
        print(f"{str(r):35s} {ms:10s} {r.endpoint}")
PY

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
echo "[i] PORT_LOCAL=$PORT"

echo "[+] Smoke POST /api/notes"
curl -i -s -X POST -H "Content-Type: application/json" \
     -d '{"text":"fix-author-fp","hours":24}' \
     "http://127.0.0.1:$PORT/api/notes" | sed -n '1,120p'

echo
echo "[+] Tail logs"
tail -n 120 "$LOG" || true
