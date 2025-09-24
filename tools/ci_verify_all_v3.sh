#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
echo "== Paso A: probe estricto =="; if ! tools/deploy_probe_strict.sh "$BASE"; then
  echo "→ Sugerencia: export RENDER_DEPLOY_HOOK=... && tools/deploy_trigger_via_hook.sh"
  exit 4
fi
echo "== Paso B: suites =="; tools/test_suite_all.sh "$BASE"
echo "== Paso C: negativos (gated) =="; tools/test_suite_negative_v6.sh "$BASE" || true
