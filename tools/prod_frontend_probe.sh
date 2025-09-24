#!/usr/bin/env bash
set -Eeuo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

echo "BASE = $BASE"
echo
echo "--- GET /api/_routes (si existe, lista rutas registradas) ---"
RJSON="$(mktemp)"
RCODE=$(curl -sS -o "$RJSON" -w '%{http_code}' "$BASE/api/_routes" || true)
echo "status: $RCODE"
if [ "$RCODE" = "200" ]; then
  echo "(primeras líneas formateadas)"
  python - <<PY || true
import json,sys
try:
  data=json.load(open("$RJSON","r",encoding="utf-8"))
  routes = data.get("routes",[])
  print("rutas:", len(routes))
  has_root = any(r.get("rule")=="/" for r in routes)
  has_js   = any(r.get("rule","").startswith("/js/") for r in routes)
  has_css  = any(r.get("rule","").startswith("/css/") for r in routes)
  print("· tiene '/'    :", has_root)
  print("· tiene '/js/*':", has_js)
  print("· tiene '/css/*':", has_css)
  # Muestra un extracto
  for r in sorted(routes, key=lambda x:x.get("rule",""))[:12]:
    print(" ", r.get("rule"), r.get("methods"))
except Exception as e:
  print("(!) JSON parse fail:", e)
PY
else
  echo "(/api/_routes no disponible en este deploy; seguimos con HEAD a rutas)"
fi
rm -f "$RJSON" || true

echo
echo "--- HEAD / ---"
curl -sSI "$BASE/" | head -n 12

echo
echo "--- HEAD /js/app.js ---"
curl -sSI "$BASE/js/app.js" | head -n 12

echo
echo "--- HEAD /css/styles.css ---"
curl -sSI "$BASE/css/styles.css" | head -n 12

echo
echo "--- HEAD /robots.txt ---"
curl -sSI "$BASE/robots.txt" | head -n 12

echo
echo "--- HEAD /api/health ---"
curl -sSI "$BASE/api/health" | head -n 12

echo
echo "Diagnóstico rápido:"
cat <<'TXT'
- Si /api/_routes muestra la regla "/" pero HEAD / da 404:
    * El blueprint está cargado, pero puede faltar index.html en FRONT_DIR del deploy.
    * Verifica que 'backend/frontend/index.html' exista en el build (este repo ya lo copia).
- Si /api/_routes NO muestra "/" y HEAD / da 404:
    * Ese proceso de gunicorn no registró el blueprint -> revisa que esté corriendo el commit más reciente.
    * Con el parche actual, tanto 'backend:app' como 'backend:create_app()' deberían registrar el blueprint.
- Si /api/health = 200 pero todo lo estático 404:
    * API vivo, frontend no montado. Suele ser por entrypoint antiguo o deploy desactualizado.
TXT
