#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
OUTDIR="${2:-/sdcard/Download}"

# 1) Auditorías runtime (deja runtime-*.txt en OUTDIR)
tools/audit_runtime_health_v3.sh "$BASE" "$OUTDIR" >/dev/null

# 2) Validaciones
pos="$(ls -1t "$OUTDIR"/runtime-positive-*.txt 2>/dev/null | head -n1 || true)"
neg="$(ls -1t "$OUTDIR"/runtime-negative-*.txt 2>/dev/null | head -n1 || true)"
dep="$(ls -1t "$OUTDIR"/runtime-deploy-*.txt   2>/dev/null | head -n1 || true)"

[[ -n "$dep" ]] || { echo "ERROR: faltó runtime-deploy-*.txt"; exit 1; }
[[ -n "$pos" ]] || { echo "ERROR: faltó runtime-positive-*.txt"; exit 1; }
[[ -n "$neg" ]] || { echo "ERROR: faltó runtime-negative-*.txt"; exit 1; }

echo "== Verificando deploy remoto==local =="
grep -qE '^remote:\s*[0-9a-f]{7,40}$' "$dep" || { echo "ERROR: deploy remoto desconocido"; cat "$dep"; exit 1; }
grep -qE '^local\s*:\s*[0-9a-f]{7,40}$'  "$dep" || { echo "ERROR: deploy local desconocido"; cat "$dep"; exit 1; }
rem="$(sed -n 's/^remote:\s*//p' "$dep")"
loc="$(sed -n 's/^local\s*:\s*//p'  "$dep")"
if [[ "$rem" != "$loc" ]]; then
  echo "ERROR: drift (remote != local):"; cat "$dep"; exit 2
fi

echo "== Verificando suite positiva (PASS=16 FAIL=0) =="
grep -q 'PASS=16 FAIL=0' "$pos" || { echo "ERROR: suite positiva no pasó"; tail -n +1 "$pos"; exit 3; }

echo "== Verificando negativos 404 (like/view/report) =="
line="$(grep -E 'negativos:' "$neg" || true)"
echo "$line"
like="$(sed -n 's/.*like=\([0-9][0-9]*\).*/\1/p' <<<"$line")"
view_get="$(sed -n 's/.*view(GET\/POST)=\([0-9][0-9]*\)\/.*/\1/p' <<<"$line")"
view_post="$(sed -n 's/.*view(GET\/POST)=[0-9]+\/\([0-9][0-9]*\).*/\1/p' <<<"$line")"
report="$(sed -n 's/.*report=\([0-9][0-9]*\).*/\1/p' <<<"$line")"

okv=false
if [[ "$view_get" == "404" || "$view_post" == "404" ]]; then okv=true; fi

if [[ "$like" != "404" || "$report" != "404" || "$okv" != "true" ]]; then
  echo "ERROR: negativos incorrectos → $line"; exit 4
fi

echo "GATE_OK: remoto==local, PASS=16, negativos 404 ✔"
