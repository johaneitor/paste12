#!/usr/bin/env bash
# Uso: tools/verify_all_behaviors_v5.sh BASE_URL [OUTDIR]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${HOME}/tmp/p12-verify-${TS}"
mkdir -p "$TMP" "$OUTDIR"
trap 'rm -rf "$TMP"' EXIT

hdr() { printf '• %s\n' "$*"; }
line() { printf '%s\n' "$*" >>"$1"; }
curl_j() { curl -fsS -H 'accept: application/json' "$@"; }
curl_h() { curl -fsS -D- -o /dev/null "$@"; }

OK=()
FAIL=()
SKIP=()

POS="$TMP/positivos.txt"
NEG="$TMP/negativos.txt"
LIM="$TMP/limits.txt"
SUM="$OUTDIR/verify-${TS}-summary.txt"

# ---------- POSITIVOS ----------
line "$POS" "== POSITIVOS =="
status=0
if curl -fsS "$BASE/" -o "$TMP/index.html" >/dev/null; then
  OK+=("GET /")
  # flags FE
  grep -qi 'name="p12-commit"' "$TMP/index.html" && OK+=("index p12-commit") || FAIL+=("index p12-commit")
  grep -qi 'p12-safe-shim' "$TMP/index.html"       && OK+=("p12-safe-shim")  || FAIL+=("p12-safe-shim")
  grep -qi '<body[^>]*data-single="1"' "$TMP/index.html" -i -E && OK+=("single-detector") || FAIL+=("single-detector")
else
  FAIL+=("GET /")
  status=1
fi

curl -fsS "$BASE/terms" -o /dev/null && OK+=("GET /terms") || FAIL+=("GET /terms")
curl -fsS "$BASE/privacy" -o /dev/null && OK+=("GET /privacy") || FAIL+=("GET /privacy")

# /api/notes GET (lista)
if curl_j "$BASE/api/notes?limit=10" -o "$TMP/notes.json" >/dev/null; then
  OK+=("GET /api/notes?limit=10")
else
  FAIL+=("GET /api/notes?limit=10")
fi

# Preflight (OPTIONS)
ALLOW="$(curl_h -X OPTIONS "$BASE/api/notes" 2>/dev/null | sed -n 's/^allow:[[:space:]]*//Ip' | tr -d '\r')"
[ -n "$ALLOW" ] || ALLOW="(sin header Allow)"
line "$POS" "Allow: $ALLOW"

# POST JSON
POST_OK=0
if curl -fsS -X POST "$BASE/api/notes" \
   -H 'content-type: application/json' -H 'accept: application/json' \
   --data '{"content":"hello from verify_v5","user":"verify","ttl_hours":1}' \
   -D "$TMP/post-json.hdr" -o "$TMP/post-json.body" ; then
  OK+=("POST /api/notes [json]")
  POST_OK=1
else
  code="$(sed -n '1s/.*[[:space:]]\([0-9][0-9][0-9]\).*/\1/p' "$TMP/post-json.hdr" 2>/dev/null || true)"
  FAIL+=("POST /api/notes [json] ($code)")
fi

# POST FORM (fallback)
if [ "$POST_OK" -eq 0 ]; then
  if curl -fsS -X POST "$BASE/api/notes" \
     -H 'accept: application/json' \
     -d 'content=hello+from+verify_v5&user=verify' \
     -D "$TMP/post-form.hdr" -o "$TMP/post-form.body" ; then
    OK+=("POST /api/notes [form]")
    POST_OK=1
  else
    code="$(sed -n '1s/.*[[:space:]]\([0-9][0-9][0-9]\).*/\1/p' "$TMP/post-form.hdr" 2>/dev/null || true)"
    FAIL+=("POST /api/notes [form] ($code)")
  fi
fi

# ---------- NEGATIVOS ----------
line "$NEG" "== NEGATIVOS =="

neg_test() {
  local label="$1"; shift
  local expect="$1"; shift
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "$@")" || code="000"
  if [ "$code" = "$expect" ]; then
    OK+=("$label $expect")
  else
    FAIL+=("$label ($code!=${expect})")
  fi
}

neg_test "like?id inexistente"      "404" "$BASE/api/like?id=99999999"
neg_test "view GET id inexistente"  "404" "$BASE/api/view?id=99999999"
neg_test "view POST id inexistente" "404" -X POST -d 'id=99999999' "$BASE/api/view"
neg_test "report?id inexistente"    "404" "$BASE/api/report?id=99999999"

# ---------- LIMITES ----------
line "$LIM" "== LIMITES (TTL/CAP) =="
if [ "$POST_OK" -ne 1 ]; then
  SKIP+=("LÍMITES (POST no disponible)")
  line "$LIM" "SKIP: no hay POST 2xx para crear notas."
else
  # Crear una ráfaga de N notas (rápido) y leer back
  N="${LIMIT_CREATE_COUNT:-25}"
  created=0
  for i in $(seq 1 "$N"); do
    if curl -fsS -X POST "$BASE/api/notes" \
      -H 'content-type: application/json' -H 'accept: application/json' \
      --data "{\"content\":\"cap_probe_$TS_$i\",\"user\":\"verify\",\"ttl_hours\":1}" \
      -o /dev/null ; then
      created=$((created+1))
    fi
  done
  line "$LIM" "creadas_ok=$created de $N"
  # Observación simple de capacidad (no asumimos CAP exacto)
  if curl_j "$BASE/api/notes?limit=100" -o "$TMP/notes-after.json"; then
    cnt="$(grep -o '"id"' "$TMP/notes-after.json" | wc -l | tr -d ' ')"
    line "$LIM" "list_count~=$cnt (post-rafaga)"
    OK+=("límites: smoke básico")
  else
    FAIL+=("límites: list post-rafaga")
  fi
fi

# ---------- RESUMEN ----------
{
  echo "----- RESUMEN (verify_v5) -----"
  echo "OK: ${#OK[@]}"; printf '  - %s\n' "${OK[@]}" 2>/dev/null || true
  echo "FAIL: ${#FAIL[@]}"; printf '  - %s\n' "${FAIL[@]}" 2>/dev/null || true
  echo "SKIP: ${#SKIP[@]}"; printf '  - %s\n' "${SKIP[@]}" 2>/dev/null || true
  echo "-------------------------------"
} > "$SUM"

# Copias visibles (máx 3 artefactos clave además del summary)
cp "$POS" "$OUTDIR/verify-${TS}-positivos.txt"
cp "$NEG" "$OUTDIR/verify-${TS}-negativos.txt"
cp "$LIM" "$OUTDIR/verify-${TS}-limits.txt"

echo "OK: verify_v5 listo → $SUM"
