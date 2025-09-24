#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="render_entry.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE (render_entry.py). Abortando."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - "$FILE" <<'PY'
import re, sys
p=sys.argv[1]
s=open(p,'r',encoding='utf-8').read()

# 1) Asegurar import del módulo y sus helpers
if "from backend.modules.interactions import" not in s:
    s = s.replace(
        "\n#  --- fin de configuración opcional ---",
        "\n#  --- fin de configuración opcional ---\nfrom backend.modules.interactions import InteractionEvent, ensure_schema, register_alias_into\n",
    ) if "#  --- fin de configuración opcional ---" in s else \
    ("from backend.modules.interactions import InteractionEvent, ensure_schema, register_alias_into\n" + s)

# 2) Hook de arranque: create table específica + ensure_schema()
if "def _ensure_interaction_table(" not in s:
    s += r"""

# === ensure: interacción (solo tabla interaction_event) ===
def _ensure_interaction_table(app, db):
    try:
        # Normalizar URL y endurecer engine si tu archivo ya tiene helpers:
        try:
            app.config["SQLALCHEMY_DATABASE_URI"] = _normalize_database_url(
                app.config.get("SQLALCHEMY_DATABASE_URI")
            )
        except Exception:
            pass
        # Crear exclusivamente la tabla de eventos (idempotente)
        from sqlalchemy import inspect
        insp = inspect(db.engine)
        if "interaction_event" not in insp.get_table_names():
            InteractionEvent.__table__.create(bind=db.engine, checkfirst=True)
        # Crear resto si faltara algo (seguro/idempotente)
        ensure_schema()
        return True
    except Exception:
        return False
"""

# 3) Invocar el hook en el arranque (una sola vez)
if "_ensure_interaction_table(" not in s or "register_alias_into(" not in s or "app.register_blueprint" not in s:
    pass  # nada
if "## interactions: startup ensure" not in s:
    # intenta encontrar un bloque donde exista `app` y `db`
    anchor = re.search(r"\n(app\s*=\s*.*?\n)", s)
    if anchor and "db = SQLAlchemy(app)" in s:
        # Inserta después del primer create_all o tras inicialización de db
        s = re.sub(
            r"(db\s*=\s*SQLAlchemy\(app\)\s*\n)",
            r"\1# ## interactions: startup ensure\ntry:\n    _ensure_interaction_table(app, db)\nexcept Exception:\n    pass\n",
            s, count=1
        )

# 4) Exponer endpoint POST /api/notes/ensure-schema (mantenimiento)
if "endpoint=\"ensure_interaction_schema\"" not in s:
    s += r"""

# === endpoint de mantenimiento: POST /api/notes/ensure-schema ===
try:
    from flask import Blueprint, jsonify
    _mnt = Blueprint("interactions_maint", __name__)

    @_mnt.post("/notes/ensure-schema", endpoint="ensure_interaction_schema")
    def ensure_interaction_schema():
        try:
            ok = _ensure_interaction_table(app, db)
            return jsonify(ok=bool(ok), created=True), (200 if ok else 500)
        except Exception as e:
            return jsonify(ok=False, error="ensure_failed", detail=str(e)), 500

    try:
        app.register_blueprint(_mnt, url_prefix="/api")
    except Exception:
        pass
except Exception:
    pass
"""

open(p,'w',encoding='utf-8').write(s)
print("[OK] render_entry.py actualizado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "feat(ops): add /api/notes/ensure-schema + startup creation for interaction_event" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'

[•] Listo. Pasos siguientes:

1) Espera a que Render haga el redeploy.
2) Ejecuta:
   APP="https://paste12-rmsk.onrender.com"
   # Forzar creación de tabla en Postgres:
   curl -si -X POST "$APP/api/notes/ensure-schema" | sed -n '1,120p'

   # Verificar diag (ya no debería dar 500/UndefinedTable):
   curl -s "$APP/api/notes/diag" | jq .

3) Probar interacciones:
   ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id')
   echo "Usando ID=$ID"
   curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
   curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
   curl -si      "$APP/api/ix/notes/$ID/stats"   | sed -n '1,160p'

Si el POST /api/notes/ensure-schema devolviera 500, revisa logs de Render y confirma:
- DATABASE_URL apunta a Postgres y contiene sslmode=require (tu hardening ya lo añade).
- La app realmente está corriendo como render_entry:app (ver /api/diag/import).
NEXT
