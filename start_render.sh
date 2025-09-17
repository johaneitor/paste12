#!/usr/bin/env bash
set -euo pipefail
# Start estable para Paste12: siempre a entry_main:app
exec gunicorn entry_main:app \
  --chdir /opt/render/project/src \
  -w "${WEB_CONCURRENCY:-2}" -k gthread --threads "${THREADS:-4}" \
  --timeout "${TIMEOUT:-120}" -b "0.0.0.0:${PORT}"
