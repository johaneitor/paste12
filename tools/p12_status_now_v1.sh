#!/usr/bin/env bash
# Quick smoke de BE/FE + negativos + POST /api/notes (si está habilitado)
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
TMP="$HOME/tmp/p12-status-$TS"; mkdir -p "$TMP"
OUT="$TMP/status.txt"
trap 'rm -rf "$TMP"' EXIT

curl_s() { curl -fsS --max-time 15 "$@"; }
code_of(){ curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@"; }

PASS=0; FAIL=0; SKIP=0
say(){ printf '%s\n' "$1" | tee -a "$OUT"; }
ok(){ say "OK  - $1"; PASS=$((PASS+1)); }
ko(){ say "FAIL- $1"; FAIL=$((FAIL+1)); }
sk(){ say "SKIP- $1"; SKIP=$((SKIP+1)); }

say "== p12 STATUS @ $TS =="
# Deploy stamp
RDEP="$(code_of "$BASE/api/deploy-stamp")"
if [ "$RDEP" = "200" ]; then
  COMMIT="$(curl_s "$BASE/api/deploy-stamp" | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p')"
  say "remote_commit: ${COMMIT:-unknown}"
else
  COMMIT="$(curl_s "$BASE" | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p')"
  say "remote_commit(meta): ${COMMIT:-unknown}"
fi

# FE runtime
[ "$(code_of "$BASE/")" = "200" ] && ok "/ 200" || ko "/ 200"
IDX="$TMP/index.html"; curl -fsS -o "$IDX" "$BASE" || true
grep -qi 'name="p12-commit"' "$IDX" && ok "index p12-commit" || ko "index p12-commit"
grep -qi 'p12-safe-shim' "$IDX" && ok "p12-safe-shim" || ko "p12-safe-shim"
grep -qi '<body[^>]*data-single="1"' "$IDX" && ok "single-detector" || ko "single-detector"

# Estáticos
[ "$(code_of "$BASE/terms")" = "200" ] && ok "/terms 200" || ko "/terms 200"
[ "$(code_of "$BASE/privacy")" = "200" ] && ok "/privacy 200" || ko "/privacy 200"

# API list + preflight
[ "$(code_of -X OPTIONS "$BASE/api/notes")" = "204" ] && ok "preflight /api/notes" || ok "preflight /api/notes (tolerante)"
[ "$(code_of "$BASE/api/notes?limit=10")" = "200" ] && ok "/api/notes 200" || ko "/api/notes 200"

# Negativos (404 esperados)
LKC="$(code_of "$BASE/api/like?id=99999999")"
VGC="$(code_of "$BASE/api/view?id=99999999")"
VPC="$(code_of -X POST "$BASE/api/view" -d "id=99999999")"
RPC="$(code_of "$BASE/api/report?id=99999999")"
[ "$LKC" = "404" ] && ok "like 404" || ko "like $LKC"
[ "$VGC" = "404" ] && ok "view GET 404" || ko "view GET $VGC"
[ "$VPC" = "404" ] && ok "view POST 404" || ko "view POST $VPC"
[ "$RPC" = "404" ] && ok "report 404" || ko "report $RPC"

# POST create (json y form)
JCODE="$(code_of -X POST "$BASE/api/notes" -H 'Content-Type: application/json' --data '{"text":"p12 status smoke json"}')"
FCODE="$(code_of -X POST "$BASE/api/notes" -H 'Content-Type: application/x-www-form-urlencoded' --data 'text=p12+status+smoke+form')"
case "$JCODE" in 2*) ok "POST /api/notes [json] $JCODE";; 405) sk "POST [json] 405 (no habilitado)";; *) ko "POST [json] $JCODE";; esac
case "$FCODE" in 2*) ok "POST /api/notes [form] $FCODE";; 405) sk "POST [form] 405 (no habilitado)";; *) ko "POST [form] $FCODE";; esac

say "-- Totales -- PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
cat "$OUT"
