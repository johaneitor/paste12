#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# === Config ===
ROOT="${1:-$(pwd)}"; cd "$ROOT"
RENDER_URL="${RENDER_URL:-https://paste12-rmsk.onrender.com}"
LOG=".tmp/paste12.log"
REPORT=".tmp/diag_integral.txt"
HOOKLOG=".tmp/author_fp_hook.log"
DB="${PASTE12_DB:-app.db}"

say(){ printf "\n[+] %s\n" "$*"; }
info(){ printf "    %s\n" "$*"; }
line(){ printf "%s\n" "$*" >>"$REPORT"; }

: > "$REPORT"

say "Resumen inicial"
line "=== DIAGNÓSTICO PASTE12 ==="
line "Fecha: $(date -Iseconds)"
line "Repositorio: $(git rev-parse --show-toplevel 2>/dev/null || echo .)"
line "Rama: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
line "HEAD: $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
git diff --quiet || line "Cambios sin commitear: SI"
line

say "Rutas declaradas en backend/routes.py"
{
  echo "---- Blueprint(s) definidos ----"
  grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*Blueprint\(' backend/routes.py || true
  echo
  echo "---- Decoradores & defs ----"
  grep -nE '^[[:space:]]*@[A-Za-z_][A-Za-z0-9_]*\.route\(|^[[:space:]]*def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\(' backend/routes.py | sed -n '1,999p' || true
} | tee -a "$REPORT"

say "Inspección de URL Map en runtime (Flask)"
python - <<'PY' 2>>".tmp/diag_integral.txt" | tee -a ".tmp/diag_integral.txt"
import sys, json
try:
    import importlib
    mod = importlib.import_module("run")
    app = getattr(mod, "app", None)
    if app is None:
        print("!! No pude importar app desde run.py")
        sys.exit(0)
    # Recolectar reglas
    rules = []
    for r in app.url_map.iter_rules():
        rules.append({
            "endpoint": r.endpoint,
            "rule": str(r),
            "methods": sorted([m for m in r.methods if m not in ("HEAD","OPTIONS")])
        })
    # Duplicados por endpoint
    from collections import defaultdict
    dup = defaultdict(list)
    for i, r in enumerate(rules):
        dup[r["endpoint"]].append(i)
    dups = {k:[rules[i] for i in idxs] for k,idxs in dup.items() if len(idxs)>1}
    print("=== URL MAP (reglas) ===")
    for r in sorted(rules, key=lambda x: (x["rule"], x["methods"])):
        print(f"{r['rule']:35s}  {','.join(r['methods']):10s}  endpoint={r['endpoint']}")
    print("\n=== Endpoints duplicados (si hay) ===")
    if dups:
        for k,v in dups.items():
            print(f"- {k}:")
            for r in v:
                print(f"    {r['rule']}  {','.join(r['methods'])}")
    else:
        print("(sin duplicados)")
    # Presencia de /api/notes
    has_get = any(r for r in rules if r["rule"]=="/api/notes" and "GET" in r["methods"])
    has_post= any(r for r in rules if r["rule"]=="/api/notes" and "POST" in r["methods"])
    print(f"\n/api/notes GET: {has_get} | POST: {has_post}")
except Exception as e:
    print("!! Error inspeccionando url_map:", repr(e))
PY

say "Verificación de esquema SQLite (tabla note)"
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  {
    echo "PRAGMA table_info(note);"
    sqlite3 "$DB" 'PRAGMA table_info(note);'
    echo
    echo "¿Tiene columna author_fp?"
    sqlite3 "$DB" 'PRAGMA table_info(note);' | awk -F'|' '{print $2}' | grep -q '^author_fp$' && echo "SI" || echo "NO"
  } | tee -a "$REPORT"
else
  info "(sin sqlite3 o sin DB local $DB)" | tee -a "$REPORT"
fi

say "Reinicio local (nohup) y captura de logs en .tmp/"
pkill -f "python .*run.py" 2>/dev/null || true
: > "$LOG" || true
: > "$HOOKLOG" || true
nohup python run.py >"$LOG" 2>&1 &
sleep 2
tail -n 60 "$LOG" | tee -a "$REPORT" || true

PORT="$(grep -Eo '127\.0\.0\.1:[0-9]+' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f2 || echo 8000)"
info "PORT_LOCAL=$PORT" | tee -a "$REPORT"

say "Smoke LOCAL /api/notes"
{
  echo "--- GET local"
  curl -i -s "http://127.0.0.1:$PORT/api/notes?page=1" | sed -n '1,60p'
  echo
  echo "--- OPTIONS local"
  curl -i -s -X OPTIONS "http://127.0.0.1:$PORT/api/notes" | sed -n '1,60p'
  echo
  echo "--- POST local"
  curl -i -s -X POST -H "Content-Type: application/json" \
       -d '{"text":"diag-integral-local","hours":24}' \
       "http://127.0.0.1:$PORT/api/notes" | sed -n '1,100p'
} | tee -a "$REPORT"

say "Smoke REMOTO (Render) /api/notes  →  $RENDER_URL"
{
  echo "--- GET remote"
  curl -i -s "$RENDER_URL/api/notes?page=1" | sed -n '1,60p'
  echo
  echo "--- OPTIONS remote"
  curl -i -s -X OPTIONS "$RENDER_URL/api/notes" | sed -n '1,60p'
  echo
  echo "--- POST remote"
  curl -i -s -X POST -H "Content-Type: application/json" \
       -d '{"text":"diag-integral-remote","hours":24}' \
       "$RENDER_URL/api/notes" | sed -n '1,100p'
} | tee -a "$REPORT"

say "Resultados clave"
# Resumen rápido en stdout
# Local status codes:
LGET=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/api/notes?page=1" || true)
LPOST=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"text":"x","hours":24}' "http://127.0.0.1:$PORT/api/notes" || true)
RGET=$(curl -s -o /dev/null -w "%{http_code}" "$RENDER_URL/api/notes?page=1" || true)
RPOST=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"text":"x","hours":24}' "$RENDER_URL/api/notes" || true)

info "Local  GET /api/notes  → $LGET"
info "Local  POST /api/notes → $LPOST"
info "Remote GET /api/notes  → $RGET"
info "Remote POST /api/notes → $RPOST"
echo
echo "[i] Reporte completo en $REPORT"
