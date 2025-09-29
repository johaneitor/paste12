#!/usr/bin/env bash
set -euo pipefail
f="wsgiapp/__init__.py"
echo "Definiciones en $f:"
grep -nE '^\s*def (like|view|report)\(' "$f" || true
