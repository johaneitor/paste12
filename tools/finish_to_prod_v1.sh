#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

# helpers
ok(){ printf "\033[32m%s\033[0m\n" "$*"; }
warn(){ printf "\033[33m%s\033[0m\n" "$*"; }
err(){ printf "\033[31m%s\033[0m\n" "$*"; }

ensure_sync(){
  if tools/deploy_probe_v3.sh "$BASE"; then
    ok "remoto == local"
  else
    warn "drift detectado → sincronizando…"
    tools/deploy_sync_v2.sh "$BASE"
  fi
}

run_audits(){
  tools/audit_full_stack_v3.sh "$BASE" "$OUTDIR" >/dev/null
  POS="$(ls -1t "$OUTDIR"/runtime-positive-*.txt | head -n1)"
  NEG="$(ls -1t "$OUTDIR"/runtime-negative-*.txt | head -n1)"
  DEP="$(ls -1t "$OUTDIR"/runtime-deploy-*.txt   | head -n1)"
  echo "# AUDIT FILES:"
  echo "  $DEP"; echo "  $POS"; echo "  $NEG"
}

check_pass(){
  grep -q 'PASS=16 FAIL=0' "$POS"
}

check_negatives(){
  line="$(grep -E 'negativos:' "$NEG" || true)"
  like="$(sed -n 's/.*like=\([0-9]\+\).*/\1/p' <<<"$line")"
  vg="$(sed -n 's/.*view(GET\/POST)=\([0-9]\+\)\/.*/\1/p' <<<"$line")"
  vp="$(sed -n 's/.*view(GET\/POST)=[0-9]\+\/\([0-9]\+\).*/\1/p' <<<"$line")"
  rep="$(sed -n 's/.*report=\([0-9]\+\).*/\1/p' <<<"$line")"
  if [[ "$like" = 404 && "$rep" = 404 && ( "$vg" = 404 || "$vp" = 404 ) ]]; then return 0; fi
  echo "$line"; return 1
}

fix_fe(){
  warn "Arreglando FE (shim+single forzado + cache-busting)…"
  tools/patch_frontend_force_shim_single_v3.sh
  tools/patch_frontend_version_assets_v1.sh || true
  git push
  tools/deploy_sync_v2.sh "$BASE"
}

fix_be(){
  warn "Arreglando BE (404 unificados)…"
  tools/patch_backend_404_unify.sh
  git push
  tools/deploy_sync_v2.sh "$BASE"
}

release_bundle(){
  ok "GATE_OK: remoto==local, PASS=16 y negativos 404"
  tools/release_tag_and_bundle_v1.sh "$OUTDIR"
}

# ---- RUN ----
ensure_sync
attempt=1
success=false
while (( attempt<=2 )); do
  echo "== Intento $attempt =="
  run_audits
  if check_pass && check_negatives; then
    success=true; break
  fi
  # decidir reparación
  if ! check_negatives; then
    fix_be
  else
    fix_fe
  fi
  ensure_sync
  attempt=$((attempt+1))
done

if ! $success; then
  err "No quedó verde en 2 intentos. Revisá $OUTDIR/runtime-*.txt y reintentá."
  exit 1
fi

release_bundle
