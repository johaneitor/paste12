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

# 1) Eliminar TODOS los handlers GET/HEAD /notes (o sin methods → GET implícito)
pat = re.compile(
    r'(@api\.route\(\s*["\']/notes["\']\s*(?:,\s*methods\s*=\s*\[[^\]]*\])?\s*\)\s*'
    r'def\s+\w+\s*\([^)]*\)\s*:\s*[\s\S]*?)(?=\n@api\.route|\Z)',
    re.S | re.I
)
parts, i, removed = [], 0, 0
for m in pat.finditer(s):
    block = m.group(0)
    mth = re.search(r'methods\s*=\s*\[([^\]]*)\]', block, re.I)
    is_get_or_head = (not mth) or any(
        w.strip().strip("'\"").lower() in ("get","head") for w in (mth.group(1).split(",") if mth else [])
    )
    parts.append(s[i:m.start()])
    if is_get_or_head:
        removed += 1  # lo quitamos
    else:
        parts.append(block)
    i = m.end()
parts.append(s[i:])
s = "".join(parts)

# 2) Insertar handler canónico
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

        # limit+1 para saber si hay próxima página
        items = q.limit(limit + 1).all()
        page = items[:limit]

        def to_dict(n):
            try:
                return _note_to_dict(n)
            except Exception:
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
        resp = jsonify([to_dict(n) for n in page])
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
Path("backend/routes.py").write_text(s, encoding="utf-8")
print(f"Handlers GET/HEAD /notes eliminados: {removed}. Handler canónico insertado.")
PY

echo "➤ Limpiar __pycache__ (por las dudas)"
find . -type d -name '__pycache__' -prune -exec rm -rf {} + 2>/dev/null || true

echo "➤ Restart dev server"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Verificación en runtime (endpoint y fuente de la función)"
python - <<'PY'
import inspect
from run import app
with app.app_context():
    print("URL rules para /api/notes:")
    for r in app.url_map.iter_rules():
        if r.rule == '/api/notes':
            print(" ", r.rule, sorted(r.methods), r.endpoint)
    fn = app.view_functions.get('api.list_notes')
    print("\nFuente de api.list_notes:\n")
    print(inspect.getsource(fn))
PY

echo "➤ Smokes: crear 3 notas para asegurar 2+ páginas"
for i in 1 2 3; do
  curl -sS -H "Content-Type: application/json" \
    -d '{"text":"pg-check","hours":24}' \
    http://127.0.0.1:8000/api/notes >/dev/null
done

echo "➤ limit=2 (debe devolver 2 items)"
curl -sS 'http://127.0.0.1:8000/api/notes?limit=2' \
  | python -c 'import sys,json;print(len(json.load(sys.stdin)))'

echo "➤ Header X-Next-After"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | sed -n '/^X-Next-After:/Ip'
NEXT="$(curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | awk -F': ' 'tolower($1)=="x-next-after"{print $2}')"
echo "NEXT=${NEXT:-<vacío>}"

echo "➤ Página 2 (si NEXT existe)"
[ -n "${NEXT:-}" ] && curl -sS "http://127.0.0.1:8000/api/notes?after_id=$NEXT&limit=2" | python -m json.tool || true

echo "➤ Commit (solo código)"
git add backend/routes.py || true
git commit -m "fix(api): unificar GET/HEAD /api/notes con paginación real (limit+cursor) y header X-Next-After" || true
