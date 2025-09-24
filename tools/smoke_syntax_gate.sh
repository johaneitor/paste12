#!/usr/bin/env bash
set -euo pipefail
echo "== surgeon v3 =="
python tools/py_syntax_surgeon_v3.py || true
echo "== gate verbose =="
python tools/py_gate_verbose.py || true
