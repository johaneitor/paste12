#!/usr/bin/env bash
# Auditoría integral (SIN redeploy) → máx 10 textos
# Uso: tools/audit_pack10_no_redeploy_v1.sh BASE_URL [/sdcard/Download]
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
PK="$OUT/p12-pack10-${TS}"
mkdir -p "$PK"

_sh() { echo "\$ $*" >>"$1"; eval "$*" >>"$1" 2>&1 || true; }
_head() { printf "\n------------------------------------------------------------\n%s\n" "$1" >>"$2"; }

# Utilidad: GET con headers+body (capado) a un archivo
_dump() {
  local url="$1" out="$2" max="${3:-5120}"
  {
    echo "### $url"
    echo "# headers:"
    curl -fsS -m 15 -D - -o /dev/null "$url" 2>&1 || true
    echo "# body (primeros ${max} bytes):"
    tmp="$(mktemp)"; curl -fsS -m 20 "$url" -o "$tmp" 2>&1 || true
    head -c "$max" "$tmp" 2>/dev/null || true
    echo
    echo "# size/sha:"
    sz="$(wc -c < "$tmp" 2>/dev/null || echo 0)"
    shasum="$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')"
    echo "bytes=$sz sha256=$shasum"
    rm -f "$tmp"
  } >>"$out"
}

# ---------- 01) Deploy stamp / Meta ----------
F1="$PK/01-deploy-stamp.txt"
{
  echo "== DEPLOY STAMP @ $TS =="
  _dump "$BASE/api/deploy-stamp" "$F1" 1024
  echo
  echo "== INDEX META p12-commit =="
  curl -fsS -m 20 "$BASE" -o "$PK/.idx.bin" -D "$PK/.idx.hdr" || true
  echo "content-type: $(grep -i '^content-type:' "$PK/.idx.hdr" | tail -1 | cut -d: -f2- | tr -d '\r' | xargs)"
  echo "cache-control: $(grep -i '^cache-control:' "$PK/.idx.hdr" | tail -1 | cut -d: -f2- | tr -d '\r' | xargs)"
  commit="$(tr -d '\0' < "$PK/.idx.bin" | sed -n 's/.*name=["'\'']p12-commit["'\''] content=["'\'']\([0-9a-f]\{7,40\}\)["'\''].*/\1/p' | head -1)"
  echo "p12-commit(meta): ${commit:-no-meta}"
} >>"$F1"

# ---------- 02) Live vs local (básico) ----------
F2="$PK/02-live-vs-local.txt"
{
  echo "== LIVE vs LOCAL (básico) =="
  # remoto
  curl -fsS -m 20 "$BASE" -o "$PK/.idx2.bin" -D "$PK/.idx2.hdr" || true
  r_len="$(wc -c < "$PK/.idx2.bin" 2>/dev/null || echo 0)"
  r_sha="$(sha256sum "$PK/.idx2.bin" 2>/dev/null | awk '{print $1}')"
  echo "remote_len=$r_len remote_sha=$r_sha"
  # local (heurística de rutas)
  for cand in backend/static/index.html static/index.html public/index.html index.html; do
    if [ -f "$cand" ]; then L="$cand"; break; fi
  done
  if [ -n "${L:-}" ]; then
    l_len="$(wc -c < "$L")"
    l_sha="$(sha256sum "$L" | awk '{print $1}')"
    echo "local_len=$l_len local_sha=$l_sha path=$L"
  else
    echo "local_index=NO_ENCONTRADO"
  fi
  echo "index_equal: $([ "${r_sha:-x}" = "${l_sha:-y}" ] && echo yes || echo no)"
} >>"$F2"

# ---------- 03) Remote deep (clave FE/headers/API) ----------
F3="$PK/03-remote-deep.txt"
{
  echo "== REMOTE DEEP =="
  _dump "$BASE/" "$F3" 2048
  _dump "$BASE/terms" "$F3" 1024
  _dump "$BASE/privacy" "$F3" 1024
  _dump "$BASE/api/notes?limit=10" "$F3" 2048
  echo "== OPTIONS /api/notes (CORS) =="
  curl -fsS -m 15 -X OPTIONS -D - -o /dev/null "$BASE/api/notes" 2>&1 || true
} >>"$F3"

# ---------- 04) Runtime positivos ----------
F4="$PK/04-runtime-positive.txt"
{
  echo "== RUNTIME POSITIVOS =="
  for p in "/" "/terms" "/privacy" "/api/health" "/api/notes?limit=10"; do
    echo "-- GET $p --"
    curl -fsS -m 20 -D - -o /dev/null "$BASE$p" || echo "FAIL $p"
  done
} >>"$F4"

# ---------- 05) Runtime negativos ----------
F5="$PK/05-runtime-negative.txt"
{
  echo "== RUNTIME NEGATIVOS =="
  echo "-- REST inexistentes (deben 404) --"
  for p in "/api/notes/999999/like" "/api/notes/999999/view" "/api/notes/999999/report"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -m 20 -H 'Accept: application/json' "$BASE$p" || echo 000)"
    echo "POST $p -> $code"
  done
  echo "-- query endpoints (deben 404) --"
  echo "GET /api/like?id=999999 -> $(curl -s -o /dev/null -w '%{http_code}' -m 15 "$BASE/api/like?id=999999" || echo 000)"
  echo "GET /api/view?id=999999 -> $(curl -s -o /dev/null -w '%{http_code}' -m 15 "$BASE/api/view?id=999999" || echo 000)"
  echo "POST /api/view -> $(curl -s -o /dev/null -w '%{http_code}' -X POST -m 15 "$BASE/api/view" || echo 000)"
  echo "GET /api/report?id=999999 -> $(curl -s -o /dev/null -w '%{http_code}' -m 15 "$BASE/api/report?id=999999" || echo 000)"
} >>"$F5"

# ---------- 06) Verify behaviors (creación JSON/FORM) ----------
F6="$PK/06-verify-behaviors.txt"
{
  echo "== VERIFY BEHAVIORS =="
  allow="$(curl -fsS -m 12 -I "$BASE/api/notes" | awk -F': ' 'tolower($1)=="allow"{print $2}' | tr -d '\r' | xargs || true)"
  echo "Allow: ${allow:-unknown}"
  echo "-- POST json --"
  curl -sS -m 20 -H 'Content-Type: application/json' -H 'Accept: application/json' \
       --data '{"text":"Hola Paste12 json desde verify","ttl_hours":12}' \
       -D - "$BASE/api/notes" -o - || true
  echo
  echo "-- POST form --"
  curl -sS -m 20 -H 'Content-Type: application/x-www-form-urlencoded' -H 'Accept: application/json' \
       --data 'text=Hola Paste12 form desde verify&ttl_hours=12' \
       -D - "$BASE/api/notes" -o - || true
} >>"$F6"

# ---------- 07) Límites (capacidad / TTL - “mejor esfuerzo”) ----------
F7="$PK/07-limits.txt"
{
  echo "== LIMITS CHECK (best-effort) =="
  echo "Intento de creación de 3 notas para observar crecimiento y headers"
  okc=0
  for i in 1 2 3; do
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 20 -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data '{"text":"Nota límite '"$i"' ................................","ttl_hours":12}' "$BASE/api/notes" || echo 000)"
    echo "POST note $i -> $code"
    [ "$code" = "201" ] && okc=$((okc+1))
  done
  echo "created_ok=$okc"
  echo
  echo "-- SAMPLE LIST --"
  curl -fsS -m 20 "$BASE/api/notes?limit=10" -H 'Accept: application/json' | head -c 4096 || true
  echo
  echo "CAP test completo omitido (CAP=200); TTL no verificable instantáneamente."
} >>"$F7"

# ---------- 08) Health y headers ----------
F8="$PK/08-health.txt"
{
  echo "== HEALTH =="
  _dump "$BASE/api/health" "$F8" 1024
} >>"$F8"

# ---------- 09) Integración FE/BE (flags, CORS) ----------
F9="$PK/09-integration-sync.txt"
{
  echo "== FE FLAGS =="
  curl -fsS -m 20 "$BASE" -o "$PK/.idx3.bin" -D "$PK/.idx3.hdr" || true
  echo "p12-commit: $(tr -d '\0' < "$PK/.idx3.bin" | sed -n 's/.*name=["'\'']p12-commit["'\''] content=["'\'']\([0-9a-f]\{7,40\}\)["'\''].*/\1/p' | head -1)"
  echo "p12-safe-shim: $(tr -d '\0' < "$PK/.idx3.bin" | grep -i -c 'p12-safe-shim')"
  echo "data-single: $(tr -d '\0' < "$PK/.idx3.bin" | sed -n 's/.*<body[^>]*data-single=["'\'']\([^"'\''>]*\)["'\''].*/\1/p' | head -1)"
  echo
  echo "== CORS /api/notes OPTIONS =="
  curl -fsS -m 15 -X OPTIONS -D - -o /dev/null "$BASE/api/notes" || true
} >>"$F9"

# ---------- 10) Repo & clones (básico, sin depender de otros tools) ----------
F10="$PK/10-repo-and-clones.txt"
{
  echo "== REPO CLEANLINESS =="
  _sh "$F10" "git status --porcelain"
  _sh "$F10" "git log -1 --oneline"
  echo
  echo "== POSIBLES DUPES FRONT/BACK (heurístico) =="
  # Busca index.html en varios paths y compara shas
  for p in backend/static/index.html static/index.html public/index.html; do
    if [ -f "\$p" ]; then
      echo "\$p sha256: \$(sha256sum "\$p" | awk '{print \$1}')"
    fi
  done
  echo
  echo "== Árbol corto =="
  _sh "$F10" "find wsgiapp -maxdepth 2 -type f | sort"
} >>"$F10"

# Índice resumen
IDX="$PK/SUMMARY.txt"
{
  echo "== p12 PACK-10 @ $TS =="
  for f in 01-deploy-stamp 02-live-vs-local 03-remote-deep 04-runtime-positive 05-runtime-negative 06-verify-behaviors 07-limits 08-health 09-integration-sync 10-repo-and-clones; do
    echo " - $f.txt"
  done
} > "$IDX"

echo "OK: pack (10 archivos máx) en: $PK"
printf "%s\n" "$PK"/{01-deploy-stamp,02-live-vs-local,03-remote-deep,04-runtime-positive,05-runtime-negative,06-verify-behaviors,07-limits,08-health,09-integration-sync,10-repo-and-clones}.txt
