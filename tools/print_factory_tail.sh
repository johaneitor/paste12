#!/usr/bin/env bash
set -euo pipefail
echo "== tail de backend/__init__.py (últimas 160 líneas) =="
nl -ba backend/__init__.py | tail -n 160
echo
echo "grep markers:"
grep -n "FAILSAFE_API_PING_ROUTES" -n backend/__init__.py || true
grep -n "app.register_blueprint(api_bp, url_prefix='/api')" backend/__init__.py || true
