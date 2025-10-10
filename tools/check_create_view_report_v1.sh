#!/usr/bin/env bash
set -euo pipefail

BASE="${1:?Uso: $0 BASE_URL}"
TMP="${HOME%/}/tmp/check_cvrs_$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

cmd() { echo "+ $*"; "$@"; }

echo "== CREAR nota (POST /api/notes) =="
resp_file="$TMP/create.json"
cmd curl -s -H 'Content-Type: application/json' -d '{"text":"verify deploy - '"$(date -u +%s)"'"}' "$BASE/api/notes" -o "$resp_file" || { echo "ERROR: POST /api/notes falló"; exit 2; }

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq no instalado en tu entorno. Instalalo para parsing JSON (pkg: jq)."; exit 3
fi

id="$(jq -r '.id // empty' "$resp_file")"
ok="$(jq -r '.ok // false' "$resp_file")"
echo "Respuesta creación: $(jq -c '.' "$resp_file")"

if [[ -z "$id" || "$ok" != "true" && "$ok" != "True" && "$ok" != "1" ]]; then
  echo "ERROR: creación no devolvió id u ok true -> Podría indicar server viejo. Salida guardada en $resp_file"
  exit 4
fi
echo "Nota creada id=$id"

echo
echo "== VISTAS (POST /api/notes/$id/view) - probar deduplicación por X-FP =="
v1="$(cmd curl -s -X POST -H 'X-FP: v1' "$BASE/api/notes/$id/view" | jq -c '.' )" || v1="$?"
v2="$(cmd curl -s -X POST -H 'X-FP: v1' "$BASE/api/notes/$id/view" | jq -c '.' )" || v2="$?"

echo "Vista 1 -> $v1"
echo "Vista 2 (mismo X-FP) -> $v2"
if [[ "$v1" == "$v2" ]]; then
  echo "OK: deduplicación aplicada (misma X-FP produce mismo estado)."
else
  echo "WARN: vistas cambiaron entre mismas X-FP — puede que no haya dedupe."
fi

echo
echo "== REPORTES (POST /api/notes/$id/report) - probar consenso 3 firmas distintas =="
r1="$(cmd curl -s -X POST -H 'X-FP: a' "$BASE/api/notes/$id/report" | jq -c '.' )" || r1="$?"
r2="$(cmd curl -s -X POST -H 'X-FP: b' "$BASE/api/notes/$id/report" | jq -c '.' )" || r2="$?"
r3="$(cmd curl -s -X POST -H 'X-FP: c' "$BASE/api/notes/$id/report" | jq -c '.' )" || r3="$?"

echo "Report 1 -> $r1"
echo "Report 2 -> $r2"
echo "Report 3 -> $r3"

# comprobar si alguno indica removed:true
removed1="$(jq -r '.removed? // false' <<<"$r1" 2>/dev/null || true)"
removed2="$(jq -r '.removed? // false' <<<"$r2" 2>/dev/null || true)"
removed3="$(jq -r '.removed? // false' <<<"$r3" 2>/dev/null || true)"

if [[ "$removed1" == "true" || "$removed2" == "true" || "$removed3" == "true" ]]; then
  echo "OK: Después de 3 reportes distintos, nota marcada removed=true (esperado)."
else
  echo "WARN: Después de 3 reportes no se marcó removed=true — la lógica de report/consenso podría no estar aplicada."
fi

echo
echo "== Chequeo final: GET /api/notes?limit=1 para ver presencia/estado =="
cmd curl -s -H 'Accept: application/json' "$BASE/api/notes?limit=10" | jq -C '.|{count: (if type=="array" then length else 1 end), sample: .[0] // .}'
