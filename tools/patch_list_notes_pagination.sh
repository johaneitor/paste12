#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

pat = r'@api\.route\("/notes", methods=\["GET"\]\)\s*def\s+list_notes\(\):[\s\S]*?(?=\n@api\.route|\Z)'
new = r"""@api.route("/notes", methods=["GET"])
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
"""
s2, n = re.subn(pat, new, s, flags=re.S)
if n == 0:
    print("WARN: list_notes() no coincidió; nada cambiado.")
else:
    p.write_text(s2, encoding="utf-8")
    print("list_notes() parchado.")
PY

# Restart rápido
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "== Smokes locales =="
curl -sS -o /dev/null -w "health=%{http_code}\n" http://127.0.0.1:8000/api/health
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | grep -i '^X-Next-After:' || echo "No hay X-Next-After (quizá menos de 2 páginas)"
