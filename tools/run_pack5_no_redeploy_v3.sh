#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR]}"
OUT="${2:-/sdcard/Download}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
DIR="$OUT/p12-pack5-$TS"
mkdir -p "$DIR"

# 01 runtime (rápido)
{
  echo "== RUNTIME @ $TS =="
  for u in "/" "/terms" "/privacy" "/api/notes?limit=1"; do
    echo "### GET $u"
    curl -fsS -D - "$BASE$u" -o /dev/null || true
    echo
  done
} > "$DIR/01-runtime.txt"

# 02 live vs local (mínimo)
{
  echo "== LIVE vs LOCAL @ $TS =="
  echo "-- HEAD local --"
  git rev-parse HEAD
  echo "-- remote deploy-stamp --"
  curl -fsS "$BASE/api/deploy-stamp" || curl -fsS "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/{"commit":"\1","source":"meta"}/p'
  echo "-- index flags --"
  curl -fsS "$BASE" | tr -d '\n' | sed 's/>< />\n/g' | grep -i -E 'p12-commit|p12-safe-shim|data-single' || true
} > "$DIR/02-live-vs-local.txt"

# 03 remote deep (básico)
{
  echo "== REMOTE DEEP @ $TS =="
  curl -fsS -D - "$BASE" -o "$DIR/index-remote.html" || true
  ls -l "$DIR/index-remote.html" || true
} > "$DIR/03-remote-deep.txt"

# 04 health (endpoints clave)
{
  echo "== HEALTH @ $TS =="
  for u in "/api/health" "/api/notes?limit=10"; do
    echo "# $u"
    curl -fsS -D - "$BASE$u" -o /dev/null || true
  done
} > "$DIR/04-health.txt"

# 05 integration & repo (negativos + git)
{
  echo "== INTEGRATION & REPO @ $TS =="
  echo "-- negativos --"
  for u in "/api/like?id=99999999" "/api/view?id=99999999" "/api/report?id=99999999"; do
    printf "%s -> %s\n" "$u" "$(curl -fsS -o /dev/null -w "%{http_code}" "$BASE$u" || true)"
  done
  echo "-- git shortlog --"
  git --no-pager log -n 5 --oneline
} > "$DIR/05-integration-and-repo.txt"

# Verificador integral resumido
tools/verify_all_behaviors_v5.sh "$BASE" "$DIR" >/dev/null || true

ls -1 "$DIR" | sed "s#^#$DIR/#"
echo "OK: pack en $DIR (máx. 10 archivos)"
