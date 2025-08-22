#!/usr/bin/env bash
set -Eeuo pipefail
ROUTES="backend/routes.py"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TMPDIR="${TMPDIR:-$PREFIX/tmp}"
LOG="$TMPDIR/paste12_server.log"
SERVER="http://127.0.0.1:8000"

cp -f "$ROUTES" "$ROUTES.bak.$(date +%s)" 2>/dev/null || true

python - <<'PY'
from pathlib import Path, re
p = Path("backend/routes.py")
s = p.read_text(encoding="utf-8")

pat = r"@api\.route\(\"/notes\", methods=\[\"POST\"\]\)\s*def\s+create_note\(\):[\s\S]*?(?=\n@|\Z)"
new = '''@api.route("/notes", methods=["POST"])
def create_note():
    # Aceptar JSON, form-data o querystring
    raw_json = request.get_json(silent=True) if request.is_json else (request.get_json(silent=True) or {})
    data = raw_json or {}
    text = (data.get("text")
            or request.form.get("text")
            or request.args.get("text")
            or "").strip()
    # hours puede venir en JSON/form/query
    hours_raw = (data.get("hours")
                 or request.form.get("hours")
                 or request.args.get("hours")
                 or 24)
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
'''
s2, n = re.subn(pat, new, s, flags=re.S)
if n == 0:
    raise SystemExit("No se encontró el handler create_note para parchear.")
p.write_text(s2, encoding="utf-8")
print("create_note parchado para aceptar JSON/form/query.")
PY

# Reinicio y smokes con CUERPO de respuesta
pkill -f "python .*run\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1

nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo ">>> Smoke JSON"
curl -sS -i -H "Content-Type: application/json" \
  -d '{"text":"nota via JSON","hours":24}' \
  "$SERVER/api/notes"

echo
echo ">>> Smoke form-data"
curl -sS -i -X POST \
  -F 'text=nota via form' \
  -F 'hours=24' \
  "$SERVER/api/notes"

echo
echo ">>> Smoke querystring"
curl -sS -i "$SERVER/api/notes?text=nota%20via%20query&hours=24"

echo
echo ">>> Tail log (si hubo error)"
tail -n 120 "$LOG" || true
