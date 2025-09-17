#!/usr/bin/env bash
set -euo pipefail
exec gunicorn render_entry:app \
  --chdir /opt/render/project/src \
  -w "${WEB_CONCURRENCY:-2}" -k gthread --threads "${THREADS:-4}" \
  --timeout "${TIMEOUT:-120}" -b "0.0.0.0:${PORT}"
