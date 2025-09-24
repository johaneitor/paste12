#!/usr/bin/env bash
set -euo pipefail

# 1) toca un nonce para invalidar caché de build
printf '%s\n' "build-nonce: $(date -u +%FT%TZ)" > .render_build_nonce

# 2) commit vacío por si no hay cambios en tree
git add .render_build_nonce >/dev/null 2>&1 || true
git commit -m "deploy: bump $(date -u +%FT%TZ)" || true

# 3) push
git push
