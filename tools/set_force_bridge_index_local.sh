#!/usr/bin/env bash
set -euo pipefail
export FORCE_BRIDGE_INDEX=1
echo "FORCE_BRIDGE_INDEX=${FORCE_BRIDGE_INDEX}"
echo "Listo. Si corrés el servidor/gunicorn a partir de este shell, '/' va a servir index.html."
