#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"

cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

pat = r"""
@api\.route\(\s*["']/notes["']\s*,\s*methods\s*=\s*\[\s*["']POST["']\s*\]\s*\)
\s*def\s+create_note\s*\(\s*\)\s*:
[\s\S]*?
(?=\n@|\Z)
"""
new = r"""@api.route("/notes", methods=["POST"])
def create_note():
    # Aceptar JSON, form-data, x-www-form-urlencoded y querystring
    raw_json = request.get_json(silent=True) or {}
    data = raw_json if isinstance(raw_json, dict) else {}

    def pick(*vals):
        for v in vals:
            if v is not None and str(v).strip() != "":
                return str(v)
        return ""

    text = pick(
        data.get("text") if isinstance(data, dict) else None,
        request.form.get("text"),
        request.values.get("text"),  # incluye querystring y form
    ).strip()

    hours_raw = pick(
        (data.get("hours") if isinstance(data, dict) else None),
        request.form.get("hours"),
        request.values.get("hours"),
        "24",
    )
    try:
        hours = int(hours_raw)
    except Exception:
        hours = 24

    if not text:
        return jsonify({"error": "text_required"}), 400

    hours = max(1, min(hours, 720))
    now = datetime.utcnow()
    try:
        n = Note(
            text=text,
            timestamp=now,
            expires_at=now + timedelta(hours=hours),
            author_fp=_fingerprint_from_request(request),
        )
        db.session.add(n)
        db.session.commit()
        return jsonify({"id": n.id, "ok": True}), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({"error": "create_failed", "detail": str(e)}), 500
"""
s2, n = re.subn(pat, new, s, flags=re.S | re.X)
if n == 0:
    raise SystemExit("No se encontró el bloque create_note para normalizar.")
p.write_text(s2, encoding="utf-8")
print("create_note normalizado (sin duplicados).")
PY

# restart rápido y smokes básicos
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "Smokes:"
curl -sS -o /dev/null -w "health=%{http_code}\n" http://127.0.0.1:8000/api/health
curl -sS -o /dev/null -w "notes_get=%{http_code}\n" http://127.0.0.1:8000/api/notes
curl -sS -o /dev/null -w "notes_post=%{http_code}\n" -H "Content-Type: application/json" \
  -d '{"text":"nota sin duplicados","hours":24}' http://127.0.0.1:8000/api/notes
