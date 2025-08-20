#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
ROOT="$(pwd)"
echo "🔎 Audit paste12 — $(date) — dir: $ROOT"
echo

# ---------- Helpers ----------
ok(){ printf "✅ %s\n" "$*"; }
warn(){ printf "⚠️  %s\n" "$*"; }
bad(){ printf "❌ %s\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

# ---------- 1) Árbol de proyecto (profundidad 3) ----------
echo "📂 Estructura (profundidad 3):"
if have tree; then
  tree -a -L 3 -I '.git|__pycache__|*.pyc'
else
  # find fallback con indent
  find . -maxdepth 3 -mindepth 1 ! -path '*/.git/*' ! -name '__pycache__' \
    | sed -E 's#^\./##' | awk -F/ '{
        pad=""; for(i=1;i<NF;i++) pad=pad "  ";
        print pad "├─ " $NF ((system("[ -d \""$0"\" ]")==0)?" /":"");
      }'
fi
echo

# ---------- 2) Greps rápidos de features en código ----------
echo "🧩 Greps de features:"
grep -RIn --color=never -E 'add_url_rule\(|@app\.route|@app\.get' backend/__init__.py || true
grep -RIn --color=never -E '/api/notes|like|report|view' backend/routes.py || true
grep -RIn --color=never -E 'Limiter|@limiter\.limit|default_limits' backend || true
grep -RIn --color=never -E 'LikeLog|ReportLog|uq_like_note_fp|uq_report_note_fp' backend/models.py || true
grep -RIn --color=never -E 'expires_at|timedelta|purge|apscheduler|BackgroundScheduler' backend || true
grep -RIn --color=never -E 'navigator\.share|clipboard|share|countdown|1080x1920|canvas' frontend/js || true
echo

# ---------- 3) Auditoría con Python (Flask + SQLAlchemy) ----------
python - <<'PY'
import os, sys, json
from pprint import pprint

print("🐍 Python audit")
sys.path.insert(0, os.getcwd())
try:
    from backend import create_app, db
    app = create_app()
except Exception as e:
    print("❌ No se pudo importar/crear app:", e)
    raise SystemExit(0)

ctx = app.app_context(); ctx.push()

# 3.1 Rutas Flask
print("\n🛣️  Rutas (rule  |  methods  |  endpoint):")
rules = sorted([(r.rule, ",".join(sorted(r.methods - {"HEAD","OPTIONS"})), r.endpoint)
                for r in app.url_map.iter_rules()], key=lambda x: x[0])
for r in rules:
    print(" -", "{:<28} | {:<18} | {}".format(*r))

# 3.2 Extensión limiter
lim = app.extensions.get("limiter")
print("\n⏱️  Rate limiter:", "OK" if lim else "NO")
if lim:
    try:
        print("   default_limits:", getattr(lim, "default_limits", None))
    except Exception:
        pass

# 3.3 DB y modelos
print("\n🗄️  DATABASE_URL:", app.config.get("SQLALCHEMY_DATABASE_URI"))
from sqlalchemy import inspect
insp = inspect(db.engine)
tables = insp.get_table_names()
print("   Tablas:", tables)

def cols(tbl):
    try:
        return [(c["name"], str(c["type"]), c.get("nullable")) for c in insp.get_columns(tbl)]
    except Exception as e:
        return [("error", str(e), False)]

for t in ("note","like_log","report_log"):
    if t in tables:
        print(f"   Columnas '{t}':", cols(t))
    else:
        print(f"   Tabla '{t}' NO existe")

# 3.4 Constraints únicas para 1 like / 1 report por persona
def uniques(tbl):
    try:
        return [uc["name"] for uc in insp.get_unique_constraints(tbl)]
    except Exception as e:
        return [f"err:{e}"]
for t in ("like_log","report_log"):
    if t in tables:
        print(f"   Unique '{t}':", uniques(t))

# 3.5 ¿columns en Note? (likes, views, reports, expires_at)
need_cols = {"note": {"likes","views","reports","expires_at","text","timestamp"}}
for t, req in need_cols.items():
    if t in tables:
        present = {c[0] for c in cols(t)}
        missing = sorted(list(req - present))
        print(f"   Faltantes en '{t}':", missing if missing else "ninguno")

# 3.6 Static/Frontend
print("\n🧱 Frontend:")
print("   app.static_folder:", app.static_folder)
for f in ("index.html","ads.txt","favicon.svg"):
    path = os.path.join(app.static_folder or "frontend", f)
    print(f"   {f}: {'OK' if os.path.isfile(path) else 'NO'}")

ctx.pop()
PY
echo

# ---------- 4) Comprobaciones de archivos frontend ----------
echo "🖼️  Front assets:"
[ -f frontend/index.html ] && ok "index.html presente" || bad "index.html NO está"
[ -f frontend/js/app.js ] && ok "frontend/js/app.js presente" || warn "frontend/js/app.js faltante"
[ -f frontend/js/share_enhancer.js ] && ok "share_enhancer.js presente" || warn "share_enhancer.js faltante"
[ -f frontend/js/hotfix.js ] && ok "hotfix.js presente" || true
[ -f frontend/ads.txt ] && ok "ads.txt presente" || warn "ads.txt faltante"
[ -f frontend/favicon.svg ] && ok "favicon.svg presente" || warn "favicon.svg faltante"

echo
echo "🧪 Checks lógicos:"
# likes/views/report endpoints
grep -qE '/api/notes/.+/like' backend/routes.py && ok "Ruta like ✔" || bad "Ruta like ❌"
grep -qE '/api/notes/.+/report' backend/routes.py && ok "Ruta report ✔" || bad "Ruta report ❌"
grep -qE '/api/notes/.+/view' backend/routes.py && ok "Ruta view ✔" || warn "Ruta view (vistas) no encontrada"

# reportes >=5 -> delete
grep -qE 'reports[ ]*>=?[ ]*5' backend/routes.py && ok "Regla borrar con ≥5 reportes ✔" || warn "No veo borrado por 5 reportes"

# 12h en backend
grep -qE 'timedelta\(hours=12\)|hours.*12' backend/routes.py && ok "Backend acepta 12h ✔" || warn "No detecto 12h en backend"

# rate limit 1/10s y 500/día
if grep -qE '@limiter\.limit\("1 per 10 ?seconds?"\)' backend/routes.py; then ok "Limit 1/10s ✔"; else warn "No veo limit 1/10s"; fi
if grep -qE '@limiter\.limit\("500 per day"\)' backend/routes.py; then ok "Limit 500/día ✔"; else warn "No veo limit 500/día"; fi

echo
ok "Fin del auditor: NO modificó nada. Usa la salida para decidir parches."
