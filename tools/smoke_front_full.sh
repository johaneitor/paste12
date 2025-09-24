#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"

_ok(){ printf "\033[32m%s\033[0m\n" "$*"; }
_warn(){ printf "\033[33m%s\033[0m\n" "$*"; }
_fail(){ printf "\033[31m%s\033[0m\n" "$*"; exit 1; }

head_code(){ curl -sS -I "$1" -o /dev/null -w '%{http_code}'; }
get_body(){ curl -sS "$1"; }
need_code_200(){
  local code="$1" name="$2"
  [[ "$code" == "200" || "$code" == "304" ]] || _fail "FAIL $name -> HTTP $code"
}

echo "== smoke_front_full @ $BASE =="

# 1) index.html
echo "-- GET / (index) --"
idx_code="$(head_code "$BASE/")"; need_code_200 "$idx_code" "HEAD /"
idx="$(get_body "$BASE/")"
echo "$idx" | grep -q '<link[^>]*href="/css/styles.css'   || _fail "FAIL: falta /css/styles.css en index"
echo "$idx" | grep -q '<link[^>]*href="/css/actions.css'  || _fail "FAIL: falta /css/actions.css en index"
echo "$idx" | grep -q '<script[^>]*src="/js/app.js'       || _fail "FAIL: falta /js/app.js en index"
echo "$idx" | grep -q '<script[^>]*src="/js/actions.js'   || _fail "FAIL: falta /js/actions.js en index"
echo "$idx" | grep -qi 'Últimas notas' && _ok "ok: título/listado presente" || _warn "WARN: no encontré 'Últimas notas' (ok si cambió el copy)"

# 2) assets HEAD
echo "-- HEAD assets --"
for path in /css/styles.css /css/actions.css /js/app.js /js/actions.js; do
  code="$(head_code "$BASE$path")"; need_code_200 "$code" "HEAD $path"
  echo "ok: $path"
done

# 3) /js/actions.js sanity (selectores y hooks)
echo "-- sanity: /js/actions.js --"
actions="$(get_body "$BASE/js/actions.js")"
echo "$actions" | grep -q 'note-menu'         || _fail "FAIL: actions.js sin 'note-menu'"
echo "$actions" | grep -q 'function deriveId' || _fail "FAIL: actions.js sin deriveId()"
echo "$actions" | grep -q 'DOMContentLoaded'  || _fail "FAIL: actions.js sin DOMContentLoaded hook"
echo "$actions" | grep -q 'MutationObserver'  || _warn "WARN: actions.js sin MutationObserver (no fatal)"
echo "$actions" | grep -q 'navigator.share'   || _warn "WARN: actions.js sin navigator.share (usa clipboard fallback?)"
echo "$actions" | grep -q '/api/notes/.*/report' || _warn "WARN: no vi fetch a /report (revisar)"
_ok "ok: actions.js contiene piezas clave"

# 4) /css/actions.css sanity
echo "-- sanity: /css/actions.css --"
acss="$(get_body "$BASE/css/actions.css")"
echo "$acss" | grep -q '\.note-menu' || _fail "FAIL: actions.css sin .note-menu"
echo "$acss" | grep -q '\.kebab'     || _fail "FAIL: actions.css sin .kebab"
echo "$acss" | grep -q '\.panel'     || _fail "FAIL: actions.css sin .panel"
_ok "ok: styles para menú"

# 5) app.js (al menos referencia al listado)
echo "-- sanity: /js/app.js --"
appjs="$(get_body "$BASE/js/app.js")"
echo "$appjs" | grep -q 'api/notes' && _ok "ok: app.js referencia /api/notes" || _warn "WARN: no encontré 'api/notes' en app.js (puede estar minificado/obfuscado)"

# 6) UI alternativa servida por backend (/api/ui) — opcional
echo "-- GET /api/ui (opcional) --"
ui_code="$(head_code "$BASE/api/ui")"
if [[ "$ui_code" == "200" || "$ui_code" == "304" ]]; then
  ui="$(get_body "$BASE/api/ui")"
  echo "$ui" | grep -q '/css/actions.css' && echo "ok: /api/ui referencia actions.css" || _warn "WARN: /api/ui sin actions.css"
  echo "$ui" | grep -q '/js/actions.js'   && echo "ok: /api/ui referencia actions.js"   || _warn "WARN: /api/ui sin actions.js"
else
  _warn "WARN: /api/ui -> HTTP $ui_code (no fatal)"
fi

# 7) endpoints mínimos que el frontend usa (para fallos visibles en UI)
echo "-- backend endpoints mínimos --"
routes_json="$(get_body "$BASE/api/_routes" | python -m json.tool 2>/dev/null || true)"
if [[ -n "$routes_json" ]]; then
  need_notes=0; need_detail=0; need_report=0; need_like=0; need_view=0
  grep -q '"/api/notes"' <<<"$routes_json" && need_notes=1
  grep -q '"/api/notes/<int:note_id>"' <<<"$routes_json" && need_detail=1
  grep -q '"/api/notes/<int:note_id>/report"' <<<"$routes_json" && need_report=1
  grep -q '"/api/notes/<int:note_id>/like"'   <<<"$routes_json" && need_like=1
  grep -q '"/api/notes/<int:note_id>/view"'   <<<"$routes_json" && need_view=1
  [[ $need_notes -eq 1 && $need_detail -eq 1 ]] || _warn "WARN: faltan rutas base de notas (la UI puede no poder cargar)"
  [[ $need_report -eq 1 ]] || _warn "WARN: falta /report (botón reportar romperá)"
  [[ $need_like   -eq 1 ]] || _warn "WARN: falta /like (botón like romperá)"
  [[ $need_view   -eq 1 ]] || _warn "WARN: falta /view (contador de vistas no subirá)"
else
  _warn "WARN: /api/_routes no devolvió JSON (ok si endpoint está deshabilitado)"
fi

echo
_ok "✅ smoke_front_full OK"
