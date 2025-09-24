#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "uso: $0 https://host"; exit 2; }
need="$(git rev-parse HEAD)"
got="$(curl -fsS "$BASE/api/deploy-stamp" | sed -n 's/.*"commit":"\([0-9a-f]\{40\}\)".*/\1/p')"

if [ "$got" != "$need" ]; then
  echo "SKIP: remoto=$got != local=$need — salto asserts de 404 (deploy atrasado)"
  # igual muestro el estado actual
  for ep in like view report; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$ep")
    echo "$ep => HTTP/$code"
  done
  exit 0
fi

echo "== Like/View/Report inexistente (espera 404) =="
fails=0
for ep in like view report; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/999999/$ep")
  echo "$ep => HTTP/$code"
  [ "$code" = "404" ] || fails=$((fails+1))
done
[ "$fails" -eq 0 ] && echo "OK: todos 404" || { echo "X: faltan 404 ($fails)"; exit 1; }
