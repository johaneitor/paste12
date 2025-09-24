#!/usr/bin/env bash
set -euo pipefail
git add contract_shim.py wsgi.py || true
git commit -m "ops: ContractShim v6 (fix paths, CORS *, Link, tests-ok)"
git push origin main
