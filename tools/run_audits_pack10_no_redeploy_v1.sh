#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
WORK="${OUT}/p12-pack10-${TS}"
mkdir -p "$WORK"

# 1) Live vs local (HTML + flags + negativos)
tools/live_vs_local_v1.sh "$BASE" "$WORK" >/dev/null || true

# 2) Runtime (smoke GET + API + headers)
tools/audit_full_stack_v3.sh "$BASE" "$WORK" >/dev/null || true

# 3) Verificador integral (positivos/negativos/límites básicos)
tools/verify_all_behaviors_v3.sh "$BASE" "$WORK" >/dev/null || true

# 4) Auditoría BE/FE/Repo/clones
tools/audit_repo_cleanliness_v4.sh "$WORK" >/dev/null || true

# 5) Health snapshot (BE/FE)
tools/health_snapshot_v1.sh "$BASE" "$WORK" >/dev/null || true || true

# Recorte a 10 textos "grandes" con nombres canónicos
i=0
for f in "$WORK"/*; do
  case "$(basename "$f")" in
    *index-remote.html|*index-local.html|*.tsv|*.json|*.bin|*.hdr) continue;;
  esac
  i=$((i+1)); mv "$f" "${WORK}/$(printf '%02d' "$i")-$(basename "$f")" || true
done

# Si quedó más de 10, comprimimos el resto en 99-EXTRA.tar.gz
CNT="$(ls -1 "${WORK}" | wc -l | tr -d ' ')"
if [ "$CNT" -gt 10 ]; then
  tar -C "$WORK" -czf "${WORK}/99-EXTRA.tgz" $(ls -1 "${WORK}" | sed -n '11,999p') || true
  ls -1 "${WORK}" | sed -n '11,999p' | xargs -I{} rm -f "${WORK}/{}" || true
fi

echo "OK: pack <=10 textos en ${WORK}"
ls -1 "${WORK}" | nl
