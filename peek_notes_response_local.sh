#!/usr/bin/env bash
set -Eeuo pipefail
URL='https://paste12-rmsk.onrender.com/api/notes?page=1'

echo "== GET $URL (Accept: application/json) =="
curl -sS -D ./hn.txt -o ./bn.txt -H 'Accept: application/json' "$URL" || true

echo
echo "---- HEADERS ----"
sed -n '1,200p' ./hn.txt

echo
echo "---- PRIMEROS 400 BYTES DEL BODY ----"
head -c 400 ./bn.txt; echo; echo

echo "---- STATUS ----"
grep -m1 -E '^HTTP/' ./hn.txt || true

echo
echo "---- PISTAS ----"
grep -Ei 'content-type|retry-after|rate|server' ./hn.txt || true
if grep -qi '<html' ./bn.txt; then echo "⚠️ Body parece HTML (no JSON)"; fi
if grep -qi 'Too Many Requests' ./bn.txt; then echo "⚠️ 429 (rate limit)"; fi
if grep -qi 'Not Found' ./bn.txt; then echo "⚠️ 404 (ruta no encontrada)"; fi
if grep -qi 'Internal Server Error' ./bn.txt; then echo "⚠️ 500 (error en servidor)"; fi
