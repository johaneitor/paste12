#!/usr/bin/env bash
set -euo pipefail
echo "== check_local_blueprint_wiring =="

echo "-- backend/routes.py: definición de Blueprint --"
grep -nE 'api\s*=\s*Blueprint\(' backend/routes.py || echo "No encontré la línea del Blueprint"

echo
echo "-- wsgiapp.py: registro del blueprint --"
grep -nE 'register_blueprint\(.+api_bp' -n wsgiapp.py || echo "No encontré app.register_blueprint(api_bp...)"

echo
echo "-- EXPECTATIVA --"
echo "routes.py => api = Blueprint(\"api\", __name__)   (SIN url_prefix aquí)"
echo "wsgiapp.py => app.register_blueprint(api_bp, url_prefix=\"/api\")"
