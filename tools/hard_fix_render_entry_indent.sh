#!/usr/bin/env bash
set -euo pipefail

f="render_entry.py"
[ -f "$f" ] || { echo "[!] No existe $f"; exit 1; }

cp -f "$f" "$f.bak.$(date +%s)"

python - <<'PY'
from pathlib import Path
p = Path("render_entry.py")
lines = p.read_text(encoding="utf-8").splitlines()

def is_import(l):
    s = l.strip()
    return s.startswith("import ") or s.startswith("from ")

# 1) Eliminar TODOS los bloques previos de NOTE_TABLE (comentario + import os + NOTE_TABLE + separador)
out=[]
i=0
while i < len(lines):
    if lines[i].strip().startswith("# --- safe default for NOTE_TABLE"):
        # consumir hasta el separador o hasta 5 líneas máximas de bloque
        j=i+1
        consumed=1
        while j < len(lines) and consumed < 8:
            if lines[j].strip().startswith("# ---") or lines[j].strip()=="":
                consumed += 1
                j += 1
                break
            consumed += 1
            j += 1
        i = j
        # saltado el bloque
        continue
    out.append(lines[i])
    i += 1

lines = out

# 2) Insertar un ÚNICO bloque NOTE_TABLE tras el último import contiguo al inicio
insert_at = 0
for idx, l in enumerate(lines):
    if is_import(l):
        insert_at = idx + 1
        continue
    # cortamos la racha de imports al primer no-import (ignorando líneas en blanco iniciales)
    if l.strip() != "":
        break

block = [
"# --- safe default for NOTE_TABLE (evita NameError al importar en Render) ---",
"import os as _os",
"NOTE_TABLE = _os.environ.get('NOTE_TABLE','note')",
"# ---------------------------------------------------------------------------",
""
]

# Evitar doble inserción si ya existe NOTE_TABLE (por seguridad)
if not any("NOTE_TABLE = _os.environ.get(" in l for l in lines):
    lines = lines[:insert_at] + block + lines[insert_at:]

# 3) Validación mínima: asegura que tras 'def create_note()' no haya líneas desindentadas
#    Encontramos la firma y verificamos que la siguiente línea NO sea a nivel 0.
for k, l in enumerate(lines):
    if l.strip().startswith("def create_note("):
        # buscar la próxima línea no vacía
        m = k+1
        while m < len(lines) and lines[m].strip()=="":
            m += 1
        if m < len(lines):
            # Si esa línea está a nivel 0, inyectamos una línea '    pass' para mantener indentación coherente
            if not lines[m].startswith((" ", "\t")):
                lines.insert(m, "    pass  # guard")
        break

Path("render_entry.py").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("OK: render_entry.py saneado (NOTE_TABLE a nivel módulo, sin duplicados, guard de indent)")
PY

echo "[+] Commit & push"
git add render_entry.py
git commit -m "fix(render_entry): move NOTE_TABLE to module scope; remove duplicates; guard indent after create_note" || true
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "[i] Ahora reintenta el deploy en Render con este Start Command en UNA sola línea:"
echo "    gunicorn render_entry:app -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --bind 0.0.0.0:\$PORT"
echo
echo "[i] Tras el redeploy, corre:"
cat <<'CMD'
APP="https://paste12-rmsk.onrender.com"
echo "[import]"; curl -sS "$APP/api/diag/import" | jq .
echo "[map]";    curl -sS "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(notes|ix)/")))' 
echo "[diag]";   curl -sS "$APP/api/notes/diag" | jq .
# si falta tabla:
curl -sS -X POST "$APP/api/notes/repair-interactions" | jq .
# elegir nota y probar
ID=$(curl -sS "$APP/api/notes?page=1" | jq -r '.[0].id // empty'); if [ -z "$ID" ]; then
  ID=$(curl -sS -X POST -H 'Content-Type: application/json' -d '{"text":"probe","hours":24}' "$APP/api/notes" | jq -r '.id'); fi
echo "ID=$ID"
curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
curl -si      "$APP/api/ix/notes/$ID/stats"    | sed -n '1,160p'
CMD
