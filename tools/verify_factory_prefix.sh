#!/usr/bin/env bash
set -euo pipefail
F="backend/__init__.py"
echo "== VERIFY factory prefix =="
echo "-- register_blueprint(api_bp, ...) --"
nl -ba "$F" | grep -n "register_blueprint(.*api_bp" -n || echo "(no se ve register_blueprint api_bp)"
echo
echo "-- create_app defs --"
grep -n "^def create_app" "$F" || echo "(no def create_app)"
echo
echo "-- primeras 220 líneas (recorte) --"
nl -ba "$F" | sed -n '1,220p'
