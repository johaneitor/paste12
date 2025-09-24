#!/usr/bin/env bash
set -euo pipefail
git add contract_shim.py wsgi.py wsgiapp/__init__.py || true
git commit -m "ops: ContractShim v5 (health txt, CORS 204, Link, FORM→JSON, view no-op) + exports" || true
git push origin main
