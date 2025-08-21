#!/usr/bin/env bash
set -Eeuo pipefail

echo "🔎 Diagnose feed & views — $(date)"
root="$(pwd)"
cd "$root"

ok(){ echo "✅ $*"; }
warn(){ echo "⚠️  $*"; }
bad(){ echo "❌ $*"; }

echo
echo "1) Validando sintaxis Python…"
if ! python -m py_compile backend/__init__.py backend/routes.py backend/models.py 2>/dev/null; then
  bad "Error de sintaxis en Python. Revisa mensajes anteriores."
  exit 1
fi
ok "Sintaxis OK"

echo
echo "2) Grep rápido de paginación y orden en backend/routes.py"
grep -nE 'bp\.get\("/notes"|/api/notes|request\.args\.get\(.page|limit\(|offset\(|order_by|timestamp\.desc|expires_at' backend/routes.py || true

echo
echo "3) Grep de vistas (ViewLog) y unicidad"
grep -nE 'class +ViewLog|view_log|@bp\.post\("/notes/.+/view' backend/models.py backend/routes.py || true
grep -nE 'UniqueConstraint.*view|uq_view' backend/models.py || true

echo
echo "4) Grep de frontend (carga paginada y listeners de vista)"
grep -nE 'fetch\(.*/api/notes|page=|loadMore|IntersectionObserver|addEventListener\(.*scroll|observe' frontend/js/app.js || true
grep -nE 'view|/view' frontend/js/app.js || true

echo
echo "5) Prueba con test client (Flask) — /api/notes?page=1..3"
python - <<'PY'
import os, sys, json, traceback
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app
except Exception as e:
    print("❌ No se pudo importar create_app:", e)
    sys.exit(0)

app = create_app()
client = app.test_client()

def try_page(p):
    r = client.get(f"/api/notes?page={p}")
    return r.status_code, r.get_data(as_text=True)[:4000]

for p in (1,2,3):
    code, body = try_page(p)
    print(f"\n— GET /api/notes?page={p} → {code}")
    if code != 200:
        print(body)
        continue
    try:
        j = json.loads(body)
        notes = j.get("notes") or j.get("data") or []
        total = j.get("total") or j.get("count") or None
        print(f"  notas: {len(notes)}  total_en_payload: {total}")
        if notes:
            head, tail = notes[0], notes[-1]
            hid = head.get("id"); hts = head.get("timestamp") or head.get("created_at")
            tid = tail.get("id"); tts = tail.get("timestamp") or tail.get("created_at")
            print(f"  1º id={hid} ts={hts}")
            print(f"  último id={tid} ts={tts}")
    except Exception:
        print("  ⚠️ no JSON o estructura inesperada. primer bytes:")
        print(body[:400])
PY

echo
echo "6) Auditoría directa a la DB actual (si existe)"
python - <<'PY'
import os, sys
sys.path.insert(0, os.getcwd())
from datetime import datetime, timezone, timedelta

try:
    from backend import create_app, db
    from backend.models import Note
except Exception as e:
    print("  ⚠️ No se pudo importar app/db/models:", e)
    sys.exit(0)

app = create_app()
with app.app_context():
    try:
        total = db.session.query(Note).count()
        print(f"   total_notas (DB actual): {total}")
        # 5 más nuevas
        newest = db.session.query(Note).order_by(Note.timestamp.desc()).limit(5).all()
        oldest = db.session.query(Note).order_by(Note.timestamp.asc()).limit(5).all()
        fmt = lambda n: f"id={n.id} ts={n.timestamp.isoformat() if n.timestamp else 'None'} likes={n.likes} views={n.views} reports={n.reports}"
        print("   top 5 más nuevas:")
        for n in newest: print("    -", fmt(n))
        print("   top 5 más viejas:")
        for n in oldest: print("    -", fmt(n))
    except Exception as e:
        print("   ⚠️ Error consultando notas:", e)

    # ViewLog si existe
    try:
        from backend.models import ViewLog
        # Duplicados últimos 24h (mismo note_id + fingerprint > 1)
        now = datetime.now(timezone.utc)
        day_ago = now - timedelta(days=1)
        rows = db.session.execute(db.text("""
            SELECT note_id, fingerprint, COUNT(*) c
            FROM view_log
            WHERE created_at >= :day_ago
            GROUP BY note_id, fingerprint
            HAVING COUNT(*) > 1
            ORDER BY c DESC
            LIMIT 10
        """), {"day_ago": day_ago}).fetchall()
        if rows:
            print("   ⚠️ Duplicados de vistas (24h):")
            for r in rows:
                print("     - note", r[0], "fp", r[1], "x", r[2])
        else:
            print("   ✅ Sin duplicados obvios en ViewLog (24h) o no hay datos.")
    except Exception as e:
        print("   ℹ️ ViewLog no está o no accesible:", e)
PY

echo
echo "7) Reglas que suelen romper paginación (heurística)"
if ! grep -q "request.args.get(\"page\"" backend/routes.py; then
  warn "No veo lectura de 'page' en backend/routes.py (se ignoraría la paginación del cliente)."
fi
if ! grep -q "order_by(Note.timestamp.desc()" backend/routes.py; then
  warn "No veo 'order_by(...desc())'; podrían aparecer las más antiguas primero."
fi
if ! grep -q "limit(" backend/routes.py || ! grep -q "offset(" backend/routes.py; then
  warn "No encuentro limit/offset en la consulta; puede que siempre devuelva la misma página."
fi

echo
echo "8) Heurística de frontend (paginación y scroll)"
if ! grep -q "page=" frontend/js/app.js; then
  warn "frontend/js/app.js no parece mandar ?page= al backend."
fi
if grep -q "addEventListener(.*scroll" frontend/js/app.js; then
  ok "Hay listener de scroll. Verifica que no se añada múltiples veces (usa {once:true})."
fi
if grep -q "IntersectionObserver" frontend/js/app.js; then
  ok "Usa IntersectionObserver; cuida detach/observe para que no dispare múltiple."
fi

echo
ok "Diagnóstico completado. Revisa los avisos arriba."
