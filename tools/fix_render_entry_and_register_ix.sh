#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

FILE="render_entry.py"
[ -f "$FILE" ] || { echo "[!] No existe $FILE; aborto."; exit 1; }

echo "[+] Backup de $FILE"
cp -f "$FILE" "$FILE.bak.$(date +%s)"

python - <<'PY'
import re, io, sys, os

p="render_entry.py"
s=open(p,"r",encoding="utf-8").read()

# 1) Asegurar NOTE_TABLE definido (una sola vez, arriba de todo tras imports)
if "NOTE_TABLE" not in s:
    # inserta luego de la primera línea de imports from/ import
    lines=s.splitlines(True)
    ins_at=0
    for i,l in enumerate(lines[:120]):
        if l.strip().startswith("from ") or l.strip().startswith("import "):
            ins_at=i
    # insertar después del último import consecutivo
    j=ins_at
    while j+1<len(lines) and (lines[j+1].strip().startswith("from ") or lines[j+1].strip().startswith("import ")):
        j+=1
    inject = (
        "\n# --- safe default for NOTE_TABLE (evita NameError al importar en Render) ---\n"
        "import os as _os\n"
        "NOTE_TABLE = _os.environ.get('NOTE_TABLE','note')\n"
        "# ---------------------------------------------------------------------------\n"
    )
    lines.insert(j+1, inject)
    s="".join(lines)

# 2) Registrar siempre interactions alias + ensure_schema al inicio de la app
if "register_alias_into(app)" not in s or "ensure_schema()" not in s:
    # Buscamos donde exista la variable 'app' creada
    # y añadimos el bloque de registro al final del archivo.
    s = s.rstrip()+"\n\n"+r"""
# === interactions: ensure schema + alias (/api/ix) ==========================
try:
    from backend.modules.interactions import register_alias_into, ensure_schema
    try:
        with app.app_context():
            ensure_schema()
    except Exception:
        pass
    try:
        register_alias_into(app)  # /api/ix/notes/<id>/(like|view|stats)
    except Exception:
        pass
except Exception:
    # si no está el módulo, no rompemos el arranque
    pass
# ===========================================================================

"""
# 3) Endpoint de reparación explícito (idempotente)
if "endpoint=\"repair_interactions\"" not in s:
    s += r"""
# --- POST /api/notes/repair-interactions: recrea esquema de interactions ----
try:
    from flask import Blueprint as _BP, jsonify as _jsonify
    _repair_bp = _BP("repair_interactions_bp", __name__)
    @_repair_bp.post("/api/notes/repair-interactions", endpoint="repair_interactions")
    def _repair_interactions():
        try:
            from backend.modules.interactions import ensure_schema
            with app.app_context():
                ensure_schema()
            return _jsonify(ok=True, note="ensure_schema() done"), 200
        except Exception as e:
            return _jsonify(ok=False, error="repair_failed", detail=str(e)), 500
    try:
        app.register_blueprint(_repair_bp)
    except Exception:
        pass
except Exception:
    pass
# ----------------------------------------------------------------------------
"""

open(p,"w",encoding="utf-8").write(s)
print("[OK] render_entry.py parchado")
PY

echo "[+] Commit & push"
git add -A
git commit -m "fix(render_entry): define NOTE_TABLE safely; ensure_schema(); register alias /api/ix; add POST /api/notes/repair-interactions" || true
git push -u --force-with-lease origin "$(git rev-parse --abbrev-ref HEAD)"

cat <<'NEXT'
[•] Hecho. Pasos:
1) Espera a que Render haga el redeploy (o fuerza un manual).
2) Verifica:
   APP="https://paste12-rmsk.onrender.com"
   curl -s "$APP/api/diag/import" | jq .
   curl -s "$APP/api/debug-urlmap" | jq '.rules | map(select(.rule|test("^/api/(ix|notes)/")))'
3) Repara/interioriza el esquema si hace falta:
   curl -si -X POST "$APP/api/notes/repair-interactions" | sed -n '1,120p'
4) Prueba interacciones:
   ID=$(curl -s "$APP/api/notes?page=1" | jq -r '.[0].id')
   echo "Usando ID=$ID"
   curl -si -X POST "$APP/api/ix/notes/$ID/like"  | sed -n '1,120p'
   curl -si -X POST "$APP/api/ix/notes/$ID/view"  | sed -n '1,120p'
   curl -si      "$APP/api/ix/notes/$ID/stats"    | sed -n '1,160p'
NEXT
