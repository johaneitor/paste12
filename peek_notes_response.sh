#!/usr/bin/env bash
set -Eeuo pipefail
URL='https://paste12-rmsk.onrender.com/api/notes?page=1'

echo "== GET $URL (con Accept: application/json) =="
curl -sS -D /tmp/hn -o /tmp/bn -H 'Accept: application/json' "$URL" || true

echo
echo "---- HEADERS ----"
cat /tmp/hn

echo
echo "---- PRIMEROS 400 BYTES DEL BODY ----"
head -c 400 /tmp/bn; echo; echo

echo "---- STATUS LINE ----"
grep -m1 -E '^HTTP/' /tmp/hn || true

echo
echo "---- POSIBLES PISTAS ----"
grep -Ei 'content-type|retry-after|rate|server' /tmp/hn || true
if grep -qi '<html' /tmp/bn; then echo "⚠️ Body parece HTML (no JSON)"; fi
if grep -qi 'Too Many Requests' /tmp/bn; then echo "⚠️ Podría ser 429 (rate limit)"; fi
if grep -qi 'Not Found' /tmp/bn; then echo "⚠️ Podría ser 404 (ruta no encontrada)"; fi
if grep -qi 'Internal Server Error' /tmp/bn; then echo "⚠️ Podría ser 500 (error en servidor)"; fi
