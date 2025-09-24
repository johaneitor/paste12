#!/usr/bin/env bash
set -Eeuo pipefail

URL='http://127.0.0.1:8000/api/notes?limit=2'
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
H="$(mktemp)"; B="$(mktemp)"

echo "➤ Reinicio rápido (por las dudas)"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Crear 3 notas dummy para forzar 2+ páginas"
for i in 1 2 3; do
  curl -sS -H 'Content-Type: application/json' \
    -d '{"text":"diag paginación","hours":24}' \
    http://127.0.0.1:8000/api/notes >/dev/null || true
done

echo
echo "➤ GET $URL (capturando headers y body)"
curl --compressed -sS -D "$H" -o "$B" "$URL" || true

echo
echo "— STATUS & HEADERS —"
sed -n '1,20p' "$H" | tr -d '\r'
CODE="$(awk 'NR==1{print $2}' "$H" || true)"
CT="$(awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' "$H" | tr -d '\r' | head -n1)"

echo
echo "— BODY (primeras 20 líneas) —"
( sed -n '1,20p' "$B" || true ) | sed 's/\x1b\[[0-9;]*m//g'  # limpia ANSI por si acaso

echo
echo "➤ Intento parsear JSON (si es application/json)"
if [[ "${CT:-}" == application/json* ]]; then
  python - <<'PY' "$B"
import sys, json, pathlib
p = pathlib.Path(sys.argv[1])
try:
    data = json.loads(p.read_text('utf-8'))
    print("OK JSON · len =", len(data) if isinstance(data, list) else "obj")
except Exception as e:
    print("JSON parse error:", e)
PY
else
  echo "Content-Type no es JSON (${CT:-desconocido}) — probablemente un error HTML."
fi

echo
echo "➤ Header X-Next-After (si hay próxima página)"
sed -n '/^X-Next-After:/Ip' "$H" | tr -d '\r' || true

echo
echo "➤ Últimas líneas del log con marca [list_notes]"
tail -n 120 "$LOG" | sed -n '/\[list_notes\]/,$p' || true

echo
echo "✔ Listo. Si hay 500, el cuerpo/headers y el log arriba te dicen el porqué."
