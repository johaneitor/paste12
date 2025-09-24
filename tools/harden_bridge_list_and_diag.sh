#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="wsgiapp/__init__.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE (bridge). Abortando."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import io, re, sys, json, os
p = "wsgiapp/__init__.py"
s = open(p, "r", encoding="utf-8").read()

# 1) Endurecer bridge_list_notes: try/except amplio + respuesta JSON
s = re.sub(
    r"@bp\.get\(\"/notes\", endpoint=\"bridge_list_notes\"\)\s*def bridge_list_notes\(\):[\s\S]*?return jsonify\(\[_note_json\(n\) for n in items]\), 200\s*[\s\S]*?@bp\.post",
    r"""@bp.get("/notes", endpoint="bridge_list_notes")
def bridge_list_notes():
    try:
        page = 1
        try:
            page = max(1, int(request.args.get("page", 1)))
        except Exception:
            page = 1
        try:
            q = Note.query.order_by(Note.timestamp.desc())
            items = q.limit(20).offset((page-1)*20).all()
            return jsonify([_note_json(n) for n in items]), 200
        except Exception as e:
            # Respuesta JSON consistente (evita HTML 500)
            return jsonify(ok=False, error="list_failed", detail=str(e)), 500
    except Exception as e:
        return jsonify(ok=False, error="list_failed", detail=str(e)), 500

@bp.post("/notes", endpoint="bridge_create_note")
""",
    s,
    flags=re.M,
)

# 2) Agregar /api/notes/diag para inspección rápida de DB y sesión
if "endpoint=\"bridge_notes_diag\"" not in s:
    insert_after = 'app.register_blueprint(bp, url_prefix="/api")'
    payload = r"""
# === Diag: /api/notes/diag (devuelve conteo y primer item) ===
@bp.get("/notes/diag", endpoint="bridge_notes_diag")
def bridge_notes_diag():
    try:
        cnt = Note.query.count()
        first = Note.query.order_by(Note.id.asc()).first()
        out = {"count": int(cnt)}
        if first is not None:
            out["first"] = _note_json(first)
        return jsonify(ok=True, diag=out), 200
    except Exception as e:
        return jsonify(ok=False, error="diag_failed", detail=str(e)), 500
"""
    s = s.replace(insert_after, payload + "\n" + insert_after)

open(p, "w", encoding="utf-8").write(s)
print("[OK] Bridge endurecido: GET /api/notes devuelve JSON en error y se añadió /api/notes/diag")
PY

echo "[+] Commit & push"
git add -A
git commit -m "bridge: harden list (JSON on error) + /api/notes/diag" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

# Nota: Render redeploy automático puede tardar algunos segundos
echo "[i] Espera unos 15-20s para que Render aplique el deploy, luego prueba:"

cat <<'CMD'
curl -s https://paste12-rmsk.onrender.com/api/health | jq .
curl -s https://paste12-rmsk.onrender.com/api/debug-urlmap | jq .
curl -s https://paste12-rmsk.onrender.com/api/notes/diag | jq .
curl -i -s 'https://paste12-rmsk.onrender.com/api/notes?page=1' | sed -n '1,120p'
CMD
