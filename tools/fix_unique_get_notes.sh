#!/usr/bin/env bash
set -Eeuo pipefail

ROUTES="backend/routes.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backup"
cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re

p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

# Elimina TODOS los handlers de GET /notes (incluye los que no especifican methods)
pat = re.compile(
    r'(@api\.route\(\s*["\']/notes["\']\s*(?:,\s*methods\s*=\s*\[([^\]]*)\])?\s*\)\s*'
    r'def\s+\w+\s*\([^)]*\)\s*:\s*[\s\S]*?)(?=\n@api\.route|\Z)',
    re.S | re.I
)

out = []
i = 0
removed = 0
for m in pat.finditer(s):
    start, end = m.span(1)
    methods = (m.group(2) or "").lower()
    is_get = ("get" in methods) or (m.group(2) is None)  # sin methods => GET implícito
    out.append(s[i:start])
    if is_get:
        removed += 1  # lo saltamos (borramos)
    else:
        out.append(s[start:end])  # conservar (p.ej. POST)
    i = end
out.append(s[i:])
s_clean = "".join(out)

canonical = r"""
@api.route("/notes", methods=["GET"])
def list_notes():
    try:
        after_id = request.args.get("after_id")
        try:
            limit = max(1, min(int(request.args.get("limit", "20")), 50))
        except Exception:
            limit = 20

        q = db.session.query(Note).order_by(Note.id.desc())
        if after_id:
            try:
                aid = int(after_id)
                q = q.filter(Note.id < aid)
            except Exception:
                pass

        items = q.limit(limit).all()

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

        resp = jsonify([_to(n) for n in items])
        if items:
            resp.headers["X-Next-After"] = str(items[-1].id)
        return resp, 200
    except Exception as e:
        return jsonify({"error": "list_failed", "detail": str(e)}), 500
""".strip()

if not s_clean.endswith("\n"):
    s_clean += "\n"
s_clean += canonical + "\n"

p.write_text(s_clean, encoding="utf-8")
print(f"Handlers GET /notes eliminados: {removed}. Handler canónico insertado.")
PY

echo "➤ Restart"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smokes"
curl -sS -o /dev/null -w "health=%{http_code}\n" http://127.0.0.1:8000/api/health

echo "— Página 1 (limit=2), ver X-Next-After —"
H="$(mktemp)"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | tee "$H" >/dev/null
awk -F': ' 'tolower($1)=="x-next-after"{print "X-Next-After:", $2}' "$H" || true
NEXT="$(awk -F': ' 'tolower($1)=="x-next-after"{print $2}' "$H" | tr -d '\r\n')"
echo "NEXT=${NEXT:-<vacío>}"

echo "— Página 2 —"
curl -sS "http://127.0.0.1:8000/api/notes?after_id=$NEXT&limit=2" | python -m json.tool || true

echo "➤ Commit (opcional)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git add backend/routes.py tools/fix_unique_get_notes.sh || true
  git commit -m "fix(api): único GET /api/notes con paginación por cursor y X-Next-After" || true
fi
