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

# Eliminar TODOS los GET/HEAD /notes y también los handlers sin methods (GET implícito)
pat = re.compile(
    r'(@api\.route\(\s*["\']/notes["\']\s*(?:,\s*methods\s*=\s*\[(?P<methods>[^\]]*)\])?\s*\)\s*'
    r'def\s+\w+\s*\([^)]*\)\s*:\s*[\s\S]*?)(?=\n@api\.route|\Z)',
    re.S | re.I
)
out, i, removed = [], 0, 0
for m in pat.finditer(s):
    start, end = m.span(1)
    methods_raw = (m.group("methods") or "")
    methods = [x.strip().lower().strip("'\"") for x in methods_raw.split(",")] if methods_raw else []
    is_get_or_head = (not methods) or any(mth in ("get", "head") for mth in methods)
    out.append(s[i:start])
    if is_get_or_head:
        removed += 1
    else:
        out.append(s[start:end])
    i = end
out.append(s[i:])
s_clean = "".join(out)

canonical = r"""
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

        # Traer limit+1 para saber si hay otra página
        items = q.limit(limit + 1).all()
        page = items[:limit]

        def to_dict(n):
            try:
                return _note_to_dict(n)  # si existe helper
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

        resp = jsonify([to_dict(n) for n in page])
        if len(items) > limit and page:
            resp.headers["X-Next-After"] = str(page[-1].id)
        return resp, 200
    except Exception as e:
        return jsonify({"error": "list_failed", "detail": str(e)}), 500
""".strip()

if not s_clean.endswith("\n"):
    s_clean += "\n"
s_clean += canonical + "\n"
p.write_text(s_clean, encoding="utf-8")
print(f"GET/HEAD /notes eliminados: {removed}. Handler canónico insertado.")
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
  git add backend/routes.py tools/hard_fix_list_pagination.sh || true
  git commit -m "fix(api): único GET/HEAD /api/notes con paginación por cursor y X-Next-After" || true
fi
