#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${1:?Uso: $0 BASE_URL}"
ts="$(date -u +%Y%m%d-%H%M%SZ)"
tmp="$HOME/tmp/p12-status-$ts"; mkdir -p "$tmp"

say(){ printf "%s\n" "$*"; }

probe_commit(){
  rc="$(curl -fsS "$BASE/api/deploy-stamp" 2>/dev/null | sed -n 's/.*"commit"[": ]*\([0-9a-f]\{7,40\}\).*/\1/p' || true)"
  if [[ -z "$rc" ]]; then
    rc="$(curl -fsS "$BASE" 2>/dev/null | sed -n 's/.*name="p12-commit" content="\([0-9a-f]\{7,40\}\)".*/\1/p' || true)"
  fi
  echo "${rc:-unknown}"
}

remote="$(probe_commit || true)"
local="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
say "== p12 STATUS @ $ts =="
say "BASE: $BASE"
say "-- Deploy probe --"
say "remote: $remote"
say "local : $local"
say "drift : $([[ "$remote" == "$local" ]] && echo aligned || echo DRIFT/$remote)"

get_code(){ curl -s -o /dev/null -w '%{http_code}' "$1" || echo "000"; }

c_root="$(get_code "$BASE/")"
c_terms="$(get_code "$BASE/terms")"
c_priv="$(get_code "$BASE/privacy")"
say ""
say "-- POSITIVOS --"
say "GET /        → $c_root"
say "GET /terms   → $c_terms"
say "GET /privacy → $c_priv"

# API quick
preflight="$(curl -sD - -o /dev/null -X OPTIONS "$BASE/api/notes" 2>/dev/null | tr -d '\r' | sed -n 's/^allow: //Ip')"
list_code="$(get_code "$BASE/api/notes?limit=10")"
say ""
say "-- API --"
say "preflight /api/notes (Allow): ${preflight:-<vacío>}"
say "list /api/notes?limit=10: code:$list_code"

exit 0
