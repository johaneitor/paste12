#!/usr/bin/env bash
# Uso: tools/verify_all_behaviors_v6.sh BASE_URL [OUTDIR]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="${HOME}/tmp/p12-verify-${TS}"
mkdir -p "$TMP" "$OUTDIR"
trap 'rm -rf "$TMP"' EXIT

hdr() { printf '• %s\n' "$*"; }
line() { printf '%s\n' "$*" >>"$1"; }
is2xx(){ case "$1" in 2*) return 0;; *) return 1;; esac; }

OK=(); FAIL=(); SKIP=()

POS="$TMP/positivos.txt"
NEG="$TMP/negativos.txt"
LIM="$TMP/limits.txt"
SUM="$OUTDIR/verify-${TS}-summary.txt"

# ---------- POSITIVOS ----------
line "$POS" "== POSITIVOS =="

root_code="$(curl -sS -o "$TMP/index.html" -w '%{http_code}' "$BASE" || echo 000)"
if is2xx "$root_code"; then
  OK+=("GET /")
  grep -qi 'name="p12-commit"' "$TMP/index.html" && OK+=("index p12-commit") || FAIL+=("index p12-commit")
  grep -qi 'p12-safe-shim' "$TMP/index.html"       && OK+=("p12-safe-shim")  || FAIL+=("p12-safe-shim")
  grep -qiE '<body[^>]*data-single="1"' "$TMP/index.html" && OK+=("single-detector") || FAIL+=("single-detector")
else
  FAIL+=("GET / ($root_code)")
fi

code_terms="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/terms" || echo 000)"
is2xx "$code_terms" && OK+=("GET /terms") || FAIL+=("GET /terms ($code_terms)")

code_priv="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/privacy" || echo 000)"
is2xx "$code_priv" && OK+=("GET /privacy") || FAIL+=("GET /privacy ($code_priv)")

code_list="$(curl -sS -H 'accept: application/json' -o "$TMP/notes.json" -w '%{http_code}' "$BASE/api/notes?limit=10" || echo 000)"
is2xx "$code_list" && OK+=("GET /api/notes?limit=10") || FAIL+=("GET /api/notes?limit=10 ($code_list)")

ALLOW="$(curl -sS -X OPTIONS -D - -o /dev/null "$BASE/api/notes" 2>/dev/null | sed -n 's/^allow:[[:space:]]*//Ip' | tr -d '\r')"
[ -n "$ALLOW" ] || ALLOW="(sin header Allow)"
line "$POS" "Allow: $ALLOW"

# POST JSON
code_post_json="$(curl -sS -X POST "$BASE/api/notes" \
   -H 'content-type: application/json' -H 'accept: application/json' \
   --data '{"content":"hello from verify_v6","user":"verify","ttl_hours":1}' \
   -D "$TMP/post-json.hdr" -o "$TMP/post-json.body" -w '%{http_code}' || echo 000)"

POST_OK=0
if is2xx "$code_post_json"; then
  OK+=("POST /api/notes [json]")
  POST_OK=1
else
  FAIL+=("POST /api/notes [json] ($code_post_json)")
  # POST FORM fallback
  code_post_form="$(curl -sS -X POST "$BASE/api/notes" \
     -H 'accept: application/json' \
     -d 'content=hello+from+verify_v6&user=verify' \
     -D "$TMP/post-form.hdr" -o "$TMP/post-form.body" -w '%{http_code}' || echo 000)"
  if is2xx "$code_post_form"; then
    OK+=("POST /api/notes [form]")
    POST_OK=1
  else
    FAIL+=("POST /api/notes [form] ($code_post_form)")
  fi
fi

# ---------- NEGATIVOS ----------
line "$NEG" "== NEGATIVOS =="

neg_test(){
  local label="$1"; local expect="$2"; shift 2
  local code="$(curl -sS -o /dev/null -w '%{http_code}' "$@" || echo 000)"
  if [ "$code" = "$expect" ]; then OK+=("$label $expect"); else FAIL+=("$label ($code!=${expect})"); fi
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
  N="${LIMIT_CREATE_COUNT:-25}"
  created=0
  for i in $(seq 1 "$N"); do
    payload="{\"content\":\"cap_probe_${TS}_$i\",\"user\":\"verify\",\"ttl_hours\":1}"
    code_c="$(curl -sS -X POST "$BASE/api/notes" \
      -H 'content-type: application/json' -H 'accept: application/json' \
      --data "$payload" -o /dev/null -w '%{http_code}' || echo 000)"
    is2xx "$code_c" && created=$((created+1))
  done
  line "$LIM" "creadas_ok=$created de $N"
  code_after="$(curl -sS -H 'accept: application/json' -o "$TMP/notes-after.json" -w '%{http_code}' "$BASE/api/notes?limit=100" || echo 000)"
  if is2xx "$code_after"; then
    cnt="$(grep -o '"id"' "$TMP/notes-after.json" | wc -l | tr -d ' ')"
    line "$LIM" "list_count~=$cnt (post-rafaga)"
    OK+=("límites: smoke básico")
  else
    FAIL+=("límites: list post-rafaga ($code_after)")
  fi
fi

# ---------- RESUMEN ----------
{
  echo "----- RESUMEN (verify_v6) -----"
  echo "OK: ${#OK[@]}"; printf '  - %s\n' "${OK[@]}" 2>/dev/null || true
  echo "FAIL: ${#FAIL[@]}"; printf '  - %s\n' "${FAIL[@]}" 2>/dev/null || true
  echo "SKIP: ${#SKIP[@]}"; printf '  - %s\n' "${SKIP[@]}" 2>/dev/null || true
  echo "-------------------------------"
} > "$SUM"

cp "$POS" "$OUTDIR/verify-${TS}-positivos.txt"
cp "$NEG" "$OUTDIR/verify-${TS}-negativos.txt"
cp "$LIM" "$OUTDIR/verify-${TS}-limits.txt"

echo "OK: verify_v6 listo → $SUM"
