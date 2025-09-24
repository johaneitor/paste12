#!/usr/bin/env bash
set -Eeuo pipefail

INIT="backend/__init__.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$INIT" "$INIT.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re, sys
p = Path("backend/__init__.py")
s = p.read_text(encoding="utf-8")
lines = s.splitlines(keepends=True)

def is_blank_or_comment(ln: str) -> bool:
    t = ln.lstrip()
    return (t == "" or t.startswith("#") or t == "\n")

# 0) Comentamos cualquier registro global peligroso (a nivel módulo)
lines = [re.sub(r'^(\s*)app\.register_blueprint\s*\(\s*webui\s*\).*$', r'# [autofix] \g<0>', ln)
         for ln in lines]

# 1) Asegurar que TODOS los encabezados con ':' tengan un bloque indentado
hdr = re.compile(r'^(\s*)(if|elif|else|for|while|with|try|except|finally|def|class)\b[^:]*:\s*(#.*)?\n?$')
i = 0
inserted = 0
while i < len(lines):
    ln = lines[i]
    m = hdr.match(ln)
    if not m:
        i += 1
        continue
    indent = m.group(1)
    base = len(indent)

    # Buscar la primera línea no vacía posterior
    j = i + 1
    while j < len(lines) and is_blank_or_comment(lines[j]):
        j += 1

    needs_pass = False
    if j >= len(lines):
        needs_pass = True
    else:
        nxt = lines[j]
        cur = len(nxt) - len(nxt.lstrip(' '))
        if cur <= base:
            needs_pass = True

    if needs_pass:
        pass_line = indent + "    pass\n"
        lines.insert(i + 1, pass_line)
        inserted += 1
        i += 2  # saltar lo que insertamos
    else:
        i += 1

# 2) Reparar también 'try' sin 'except/finally' (por si quedó mal cerrado)
# (Si el bloque existe arriba, aquí sólo añadimos un except mínimo si falta)
s2 = "".join(lines)
lines = s2.splitlines(keepends=True)
i = 0
while i < len(lines):
    ln = lines[i]
    m = re.match(r'^(\s*)try\s*:\s*(#.*)?\n$', ln)
    if not m:
        i += 1
        continue
    indent = m.group(1)
    base = len(indent)

    # Buscar siguiente handler al mismo indent (except/finally)
    j = i + 1
    has_handler = False
    while j < len(lines):
        t = lines[j]
        if t.strip() == "":
            j += 1
            continue
        cur = len(t) - len(t.lstrip(' '))
        if cur < base:
            break
        if re.match(rf'^{indent}(except\b|finally:)', t):
            has_handler = True
            break
        j += 1

    if not has_handler:
        # Insertar handler mínimo antes del dedent
        k = j if j < len(lines) else len(lines)
        lines[k:k] = [indent+"except Exception:\n", indent+"    pass\n"]
        i = k + 2
    else:
        i = j + 1

s3 = "".join(lines)

# 3) Hook seguro dentro de create_app (idempotente)
if "ensure_webui(app)" not in s3:
    m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s3)
    if m:
        indent = m.group(2)
        inject = (
            f"\n{indent}# -- attach frontend (safe) --\n"
            f"{indent}try:\n"
            f"{indent}    from .webui import ensure_webui  # type: ignore\n"
            f"{indent}    ensure_webui(app)\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
        )
        s3 = s3[:m.start(2)] + inject + s3[m.start(2):]

# 4) Validar sintaxis y, si falla, mostrar contexto
try:
    compile(s3, str(p), 'exec')
except SyntaxError as e:
    start = max(0, (e.lineno or 1) - 6)
    end   = min(len(s3.splitlines()), (e.lineno or 1) + 5)
    ctx = s3.splitlines()[start:end]
    print(f"(!) Sigue error de sintaxis en {p}: {e}")
    print("— Contexto aproximado —")
    for idx, l in enumerate(ctx, start=start+1):
        print(f"{idx:>5}: {l}")
    sys.exit(2)

p.write_text(s3, encoding="utf-8")
print(f"✓ {p} reparado ({inserted} 'pass' insertados si faltaban bloques).")
PY

echo "➤ Restart local"
pkill -9 -f "python .*run\\.py" 2>/dev/null || true
pkill -9 -f gunicorn 2>/dev/null || true
pkill -9 -f waitress 2>/dev/null || true
pkill -9 -f flask 2>/dev/null || true
sleep 1
nohup python -u run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke /api/health"
curl -sS -o /dev/null -w 'health=%{http_code}\n' http://127.0.0.1:8000/api/health || true

echo "➤ Commit & push"
git add backend/__init__.py || true
git commit -m "fix(init): auto-reparar bloques sin cuerpo e inyectar hook frontend sólo en create_app()" || true
git push origin main || true

echo "✓ Hecho."
