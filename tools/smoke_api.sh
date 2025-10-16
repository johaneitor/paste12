#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-${BASE:-https://paste12-rmsk.onrender.com}}"
echo "== smoke_api @ $BASE =="

H="$(mktemp)"; B="$(mktemp)"; trap 'rm -f "$H" "$B"' EXIT

req() {
  local method="$1" path="$2" data="${3:-}"
  : >"$H"; : >"$B"
  if [[ -n "$data" ]]; then
    code=$(curl -sS -D "$H" -o "$B" -X "$method" -H 'Content-Type: application/json' --data "$data" "$BASE$path" -w '%{http_code}')
  else
    code=$(curl -sS -D "$H" -o "$B" -X "$method" "$BASE$path" -w '%{http_code}')
  fi
  printf "%s" "$code"
}

ctype() { grep -i '^content-type:' "$H" | tail -1 | cut -d' ' -f2- | tr -d '\r'; }

pp() {
  if printf '%s' "$(ctype)" | grep -qi 'application/json'; then
    python -m json.tool < "$B" 2>/dev/null || cat "$B"
  else
    head -c 400 "$B"; echo
  fi
}

must_json_true() {
  # Uso: must_json_true "expr1" "expr2" ...
  # Lee el JSON desde $B (ruta), NO desde stdin.
  python - "$B" "$@" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, "rb"))
for expr in sys.argv[2:]:
    try:
        ok = eval(expr, {}, {"data": data})
        if not ok:
            print("FAIL cond:", expr)
            sys.exit(2)
    except Exception as e:
        print("FAIL eval:", expr, e)
        sys.exit(2)
print("ok")
PY
}

echo
echo "-- GET /api/health --"
c=$(req GET /api/health); echo "status:$c"
pp
[[ "$c" == 200 ]] || { echo "FAIL /api/health"; exit 1; }
must_json_true "data.get('ok')==True" >/dev/null

echo
echo "-- GET /__api_import_error (esperado 404) --"
c=$(req GET /__api_import_error); echo "status:$c"
[[ "$c" == 404 ]] || { echo "FAIL __api_import_error no es 404"; exit 1; }

echo
echo "-- GET /__whoami (blueprint 'api' y rutas detalle) --"
c=$(req GET /__whoami); echo "status:$c"
pp
if [[ "$c" == 200 ]]; then
  must_json_true "'api' in data.get('blueprints', [])" "data.get('has_detail_routes')==True" >/dev/null || \
    echo "WARN __whoami payload inesperado (continuo)"
else
  echo "WARN /__whoami no disponible (continuo)"
fi

echo
echo "-- GET /api/_routes (debe listar endpoints de notas) --"
c=$(req GET /api/_routes); echo "status:$c"
pp
if [[ "$c" == 200 ]]; then
python - "$B" <<'PY'
import json, sys
routes = {r.get("rule") for r in json.load(open(sys.argv[1]))["routes"]}
need = {
  "/api/notes",
  "/api/notes/<int:note_id>",
  "/api/notes/<int:note_id>/like",
  "/api/notes/<int:note_id>/report",
  "/api/notes/<int:note_id>/view",
}
missing = need - routes
if missing:
    print("FAIL faltan reglas:", sorted(missing))
    sys.exit(2)
print("ok")
PY
rc=$?; [[ $rc -eq 0 ]] || echo "WARN /api/_routes incompleto (continuo)"
else
  echo "WARN /api/_routes no disponible (continuo)"
fi

echo
echo "-- POST /api/notes (crear) --"
ts=$(date -u +%FT%TZ)
data=$(printf '{"text":"smoke %s","hours":24}' "$ts")
c=$(req POST /api/notes "$data"); echo "status:$c"
pp
[[ "$c" == 201 ]] || { echo "FAIL crear nota"; exit 1; }

# Extraer ID de forma robusta (Python y fallback a jq)
ID="$(python -c 'import json,sys;print(json.load(open(sys.argv[1]))["id"])' "$B" 2>/dev/null || true)"
if [[ -z "${ID:-}" ]] && command -v jq >/dev/null 2>&1; then
  ID="$(jq -r '.id // empty' "$B" 2>/dev/null || true)"
fi
[[ -n "${ID:-}" ]] || { echo "FAIL no pude extraer ID. Body:"; cat "$B"; exit 1; }
echo "ID=$ID"

echo
echo "-- POST /api/notes/$ID/view --"
c=$(req POST "/api/notes/$ID/view"); echo "status:$c"
pp
[[ "$c" == 200 ]] || echo "WARN /view !=200 (ok si silente)"

echo
echo "-- POST /api/notes/$ID/like --"
c=$(req POST "/api/notes/$ID/like"); echo "status:$c"
pp
[[ "$c" == 200 ]] || echo "WARN /like !=200"

echo
echo "-- POST /api/notes/$ID/report --"
c=$(req POST "/api/notes/$ID/report"); echo "status:$c"
pp
[[ "$c" == 200 ]] || echo "WARN /report !=200"

echo
echo "-- GET /api/notes/$ID (ver contadores) --"
c=$(req GET "/api/notes/$ID"); echo "status:$c"
pp
if [[ "$c" != 200 ]]; then
  echo "WARN detalle no disponible; intento verificar por listado"
  c=$(req GET "/api/notes?limit=100&wrap=1"); echo "status:$c"
  if [[ "$c" == 200 ]]; then
    python - "$B" "$ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
id_ = int(sys.argv[2])
items = (data.get("items") or data)
ids = { (i.get("id") if isinstance(i, dict) else None) for i in items }
assert id_ in ids, "missing id in list"
print("ok in list")
PY
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "FAIL get nota individual"; exit 1
    fi
  else
    echo "FAIL get nota individual"; exit 1
  fi
fi

echo
echo "-- GET /api/dbdiag --"
c=$(req GET /api/dbdiag); echo "status:$c"
pp
if [[ "$c" == 200 ]]; then
  must_json_true "data.get('engine_ok')==True" "data.get('session_bind')==True" >/dev/null || \
    echo "WARN /api/dbdiag payload inesperado (continuo)"
else
  echo "WARN /api/dbdiag no disponible (continuo)"
fi

echo
echo "✅ smoke_api OK (ID=$ID)"
