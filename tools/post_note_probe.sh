#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 https://host}"
txt="${2:-ttl probe default}"

probe() {
  local label="$1"; shift
  echo "---- $label ----"
  curl -sS -i -H 'Accept: application/json' -H 'Content-Type: application/json' "$BASE/api/notes" "$@"
  echo
}

# A) estilo “-d {json}”
probe "A: -d inline JSON" \
  -d "{\"text\":\"$txt\"}"

# B) estilo seguro con stdin (evita escapes raros)
probe "B: --data-binary @- (stdin JSON)" \
  --data-binary @- <<EOF
{"text":"$txt"}
EOF

# C) con jq (si está) — arma JSON correcto aunque haya caracteres raros
if command -v jq >/dev/null 2>&1; then
  jq -n --arg t "$txt" '{text:$t}' \
  | probe "C: jq -n {text:\$t}" --data-binary @-
else
  echo "(aviso) jq no está, omito variante C"
fi
