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

# Eliminar cualquier handler GET/HEAD para /notes
pat = re.compile(
    r'(@api\.route\(\s*["\']/notes["\']\s*(?:,\s*methods\s*=\s*\[[^\]]*\])?\s*\)\s*def\s+\w+\s*\([^)]*\)\s*:\s*[\s\S]*?)(?=\n@api\.route|\Z)',
    re.S | re.I
)
parts = []
i = 0
removed = 0
for m in pat.finditer(s):
    block = m.group(0)
    # Si el bloque maneja GET/HEAD o no declara methods (implícito GET), lo quitamos
    mth = re.search(r'methods\s*=\s*\[([^\]]*)\]', block, re.I)
    if not mth or any(w.strip().strip("'\"").lower() in ("get","head") for w in (mth.group(1).split(",") if mth else [])):
        parts.append(s[i:m.start()])
        i = m.end()
        removed += 1
parts.append(s[i:])
s = "".join(parts)

# Handler canónico con limit, cursor y header
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

        # Traemos limit+1 para saber si hay próxima página
        items = q.limit(limit + 1).all()
        page = items[:limit]

        def to_dict(n):
            try:
                return _note_to_dict(n)  # si existiera helper
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
  curl -sS -H "Content-Type: application/json" \
    -d '{"text":"paginacion smoke","hours":24}' \
    http://127.0.0.1:8000/api/notes >/dev/null
done

echo "➤ limit=2 (debe devolver 2 items)"
curl -sS 'http://127.0.0.1:8000/api/notes?limit=2' \
  | python -c 'import sys,json;print(len(json.load(sys.stdin)))'

echo "➤ Header X-Next-After"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | sed -n '/^X-Next-After:/Ip'

NEXT="$(curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | awk -F': ' 'tolower($1)=="x-next-after"{print $2}')"
echo "NEXT=${NEXT:-<vacío>}"

echo "➤ Página 2"
curl -sS "http://127.0.0.1:8000/api/notes?after_id=$NEXT&limit=2" | python -m json.tool || true

echo "➤ Commit (solo código, el script puede estar gitignored)"
git add backend/routes.py || true
git commit -m "fix(api): forzar handler canónico GET/HEAD /api/notes con paginación (limit+cursor) y X-Next-After" || true
