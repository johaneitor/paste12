#!/usr/bin/env bash
set -Eeuo pipefail
URL="${1:-https://paste12-rmsk.onrender.com/api/notes?page=1}"

tmpdir="$(mktemp -d)"
body="$tmpdir/body.bin"
meta="$tmpdir/meta.txt"

# -w imprime código/ctype a stdout; -o guarda body
curl -sS -H 'Accept: application/json' \
  -w 'HTTP_CODE:%{http_code}\nCONTENT_TYPE:%{content_type}\n' \
  "$URL" -o "$body" > "$meta" || true

code="$(grep -E '^HTTP_CODE:' "$meta" | cut -d: -f2)"
ctype="$(grep -E '^CONTENT_TYPE:' "$meta" | cut -d: -f2)"
len="$(wc -c < "$body" | tr -d ' ')"

echo "→ $URL"
echo "  http_code=$code  content_type=$ctype  body_len=$len"

# Si no es 200 o no es JSON, mostrar primeros bytes y salir
if [ "$code" != "200" ] || ! echo "$ctype" | grep -qi json; then
  echo "  ⛔ No es JSON 200. Primeros 400 bytes del cuerpo:"
  head -c 400 "$body" ; echo
  exit 1
fi

# Parsear seguro
python - <<'PY' "$body"
import sys, json
p=sys.argv[1]
with open(p,'rb') as f:
    s=f.read()
print("  JSON ok, len =", len(s))
d=json.loads(s)
ns=d.get("notes",[])
print("  page:", d.get("page"), "page_size:", d.get("page_size"), "has_more:", d.get("has_more"))
print("  count(notes):", len(ns))
print("  ids:", [n.get("id") for n in ns])
PY
