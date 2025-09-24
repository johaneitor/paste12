#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-$(pwd)}"; cd "$ROOT"

echo "[+] 1/4 Esquema: eventos + constraints (sin unlike)…"
bash tools/migrate_events_and_constraints.sh

echo "[+] 2/4 Escribiendo módulo encapsulado backend/modules/interactions.py…"
bash tools/write_interactions_module.sh

echo "[+] 3/4 Registrando módulo (idempotente) en wsgi.py o run.py…"
bash tools/patch_register_interactions.sh

echo "[+] 4/4 Test integral end-to-end…"
bash tools/test_integral_interactions.sh

echo "[✓] Listo. Si querés subir cambios:"
echo "    bash tools/commit_push_all.sh 'feat: interactions module (events + counters, no-unlike) + e2e tests'"
