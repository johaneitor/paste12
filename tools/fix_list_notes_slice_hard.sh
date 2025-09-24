#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# 1) Eliminar TODOS los handlers /api/notes que sean GET/HEAD (dejamos POST intacto)
pat = re.compile(
    r'(@api\.route\(\s*["\']/notes["\']\s*(?:,\s*methods\s*=\s*\[[^\]]*\])?\s*\)\s*'
    r'def\s+(\w+)\s*\([^)]*\)\s*:\s*[\s\S]*?)(?=\n@api\.route|\Z)',
    re.S | re.I
)
out=[]; i=0; removed=0
for m in pat.finditer(s):
    start, end = m.span(1)
    name = m.group(2)
    block = s[start:end]
    # Si no especifica methods => GET implícito
    mth = re.search(r'methods\s*=\s*\[([^\]]*)\]', block, re.I)
    if mth:
        methods = mth.group(1).lower()
        is_getlike = ('get' in methods) or ('head' in methods)
    else:
        is_getlike = True  # sin methods -> GET por defecto

    out.append(s[i:start])
    if is_getlike:
        removed += 1
    else:
        out.append(block)  # conservar p.ej. POST /notes
    i = end
out.append(s[i:])
s = "".join(out)

# 2) Limpiar cualquier rastro de prints de diagnóstico rotos
s = re.sub(r'.*\[list_notes\].*\n', '', s)

# 3) Insertar handler canónico correcto
canonical = r'''
@api.route("/notes", methods=["GET", "HEAD"])
def list_notes():
    try:
        after_id = request.args.get("after_id")
        try:
            limit = int((request.args.get("limit") or "20").strip() or "20")
        except Exception:
            limit = 20
        limit = max(1, min(limit, 50))

        q = db.session.query(Note).order_by(Note.id.desc())
        if after_id:
            try:
                aid = int(after_id)
                q = q.filter(Note.id < aid)
            except Exception:
                pass

        # Traer limit+1 para detectar si hay otra página
        items = q.limit(limit + 1).all()
        page = items[:limit]

        def _to(n):
            return {
                "id": n.id,
                "text": getattr(n, "text", None),
                "timestamp": n.timestamp.isoformat() if getattr(n, "timestamp", None) else None,
                "expires_at": n.expires_at.isoformat() if getattr(n, "expires_at", None) else None,
                "likes": getattr(n, "likes", 0) or 0,
                "views": getattr(n, "views", 0) or 0,
                "reports": getattr(n, "reports", 0) or 0,
            }

        from flask import jsonify
        resp = jsonify([_to(n) for n in page])
        if len(items) > limit and page:
            resp.headers["X-Next-After"] = str(page[-1].id)
        return resp, 200
    except Exception as e:
        from flask import jsonify
        return jsonify({"error": "list_failed", "detail": str(e)}), 500
'''.strip()

if not s.endswith("\n"):
    s += "\n"
s += canonical + "\n"

p.write_text(s, encoding="utf-8")
print(f"GET/HEAD /notes removidos: {removed}. Handler canónico insertado.")
PY

echo "➤ Restart dev server"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes: crear 3 notas para forzar 2+ páginas"
for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' -d '{"text":"page slice smoke","hours":24}' \
    http://127.0.0.1:8000/api/notes >/dev/null || true
done

echo "➤ limit=2 (debe devolver 2 ítems)"
curl -sS 'http://127.0.0.1:8000/api/notes?limit=2' \
  | python - <<'PY'
import sys, json
try:
    data = json.load(sys.stdin)
    print(len(data))
except Exception as e:
    print("JSON parse error:", e)
PY

echo "➤ Header X-Next-After (si hay más páginas)"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | sed -n '/^X-Next-After:/Ip' || true

echo "➤ Página 2 (si existe NEXT)"
NEXT="$(curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | awk -F': ' 'tolower($1)=="x-next-after"{print $2}')"
if [ -n "${NEXT:-}" ]; then
  curl -sS "http://127.0.0.1:8000/api/notes?after_id=$NEXT&limit=2" | python -m json.tool || true
fi

echo "➤ Verificar runtime (mapea rutas y muestra fuente real)"
python - <<'PY'
import inspect
from run import app
with app.app_context():
    rules = [r for r in app.url_map.iter_rules() if r.rule == '/api/notes']
    for r in rules:
        print("RULE:", r.rule, sorted(r.methods), r.endpoint)
    f = app.view_functions.get('api.list_notes')
    print("\nFUNC:", f)
    try:
        print("\nSOURCE:\n" + inspect.getsource(f))
    except Exception as e:
        print("No pude obtener source:", e)
PY

echo "➤ Commit"
git add backend/routes.py || true
git commit -m "fix(api): reemplazo canónico de list_notes para devolver page (slice) y X-Next-After correcto" || true

echo "✓ Listo."
