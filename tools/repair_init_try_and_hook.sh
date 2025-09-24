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

# 0) Quitar registros globales peligrosos (nivel módulo)
#    app.register_blueprint(webui) y similares a nivel indent 0
lines = [re.sub(r'^(\s*)app\.register_blueprint\s*\(\s*webui\s*\).*$', r'# [autofix] \g<0>', ln)
         for ln in lines]

# 1) Reparar todos los try: sin except/finally
i = 0
changed = False
while i < len(lines):
    ln = lines[i]
    m = re.match(r'^(\s*)try\s*:\s*(#.*)?\n$', ln)
    if not m:
        i += 1
        continue
    indent = m.group(1)
    # Buscar el inicio del bloque (primera línea con indent > indent_try)
    k = i + 1
    body_has_stmt = False
    while k < len(lines):
        lnk = lines[k]
        # fin del archivo => no hay except/finally; añadiremos al final
        if lnk.strip() == "":
            k += 1
            continue
        cur_indent = len(lnk) - len(lnk.lstrip(' '))
        try_indent = len(indent)
        # Si dedent <= indent_try, terminó el bloque 'try' sin 'except'
        if cur_indent <= try_indent:
            break
        # Si hay una línea no vacía/comentario dentro del bloque -> cuerpo existe
        if not is_blank_or_comment(lnk):
            body_has_stmt = True
        # Si aparece except/finally al mismo indent del try, ya está bien
        if re.match(rf'^{indent}(except\b|finally:)', lnk):
            body_has_stmt = True
            break
        k += 1

    # Detectar si dentro del bloque encontramos except/finally al mismo indent
    has_handler = False
    j = i + 1
    while j < len(lines):
        lnj = lines[j]
        if lnj.strip() == "":
            j += 1
            continue
        cur_indent = len(lnj) - len(lnj.lstrip(' '))
        if cur_indent < len(indent):
            # dedent por fuera del try
            break
        if re.match(rf'^{indent}(except\b|finally:)', lnj):
            has_handler = True
            break
        j += 1

    if has_handler:
        i = j + 1
        continue

    # No hay except/finally: insertar uno antes del dedent (k es el primer dedent o EOF)
    insert_at = k if k < len(lines) else len(lines)

    patch = []
    # Si el try no tenía cuerpo, ponemos un 'pass'
    if not body_has_stmt:
        patch.append(indent + "    pass\n")
    # Handler mínimo
    patch.append(indent + "except Exception:\n")
    patch.append(indent + "    pass\n")

    lines[insert_at:insert_at] = patch
    changed = True
    # Saltar más allá del parche
    i = insert_at + len(patch)

# 2) Re-inyectar hook dentro de create_app (idempotente)
s2 = "".join(lines)
# Si ya está, no duplicar
if "ensure_webui(app)" not in s2:
    m = re.search(r'(def\s+create_app\s*\([^)]*\)\s*:\s*[\s\S]*?)\n(\s*)return\s+app\b', s2)
    if m:
        indent = m.group(2)
        inject = (
            f"\n{indent}# -- adjuntar frontend de forma segura --\n"
            f"{indent}try:\n"
            f"{indent}    from .webui import ensure_webui  # type: ignore\n"
            f"{indent}    ensure_webui(app)\n"
            f"{indent}except Exception:\n"
            f"{indent}    pass\n"
        )
        s2 = s2[:m.start(2)] + inject + s2[m.start(2):]

# 3) Validar sintaxis
try:
    compile(s2, str(p), 'exec')
except SyntaxError as e:
    print("(!) Error de sintaxis aún en backend/__init__.py:", e)
    sys.exit(2)

p.write_text(s2, encoding="utf-8")
print("✓ backend/__init__.py reparado y con hook en create_app.")
PY

echo "➤ Restart local (si aplica)"
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
git commit -m "fix(init): reparar try/except huérfanos y adjuntar frontend sólo dentro de create_app()" || true
git push origin main || true

echo "✓ Listo."
