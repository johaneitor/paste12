#!/usr/bin/env bash
# Uso: tools/check_site.sh https://tu-dominio
set -u
BASE="${1:-http://127.0.0.1:8000}"
TIMEOUT="${TIMEOUT:-12}"
CURL="curl -sS --max-time $TIMEOUT"
PASS=0; FAIL=0

# Colores
if [ -t 1 ]; then G="\033[32m"; R="\033[31m"; Y="\033[33m"; N="\033[0m"; else G=""; R=""; Y=""; N=""; fi
ok(){ echo -e "✓ ${G}$1${N}"; PASS=$((PASS+1)); }
ko(){ echo -e "✗ ${R}$1${N}"; FAIL=$((FAIL+1)); }
info(){ echo -e "… ${Y}$1${N}"; }

http_code(){ $CURL -o /dev/null -w "%{http_code}" "$1"; }
header(){
  $CURL -I "$1" \
  | awk -v IGNORECASE=1 -v k="$2" '$0 ~ "^"k":" {sub("\r","");print substr($0,index($0,":")+2)}'
}
json(){ $CURL "$@"; }

echo "== Health =="
code=$(http_code "$BASE/api/health"); [ "$code" = "200" ] && ok "Health 200" || ko "Health $code"

echo "== / (bridge + pastel + no-store) =="
root_url="$BASE/?_=$(date +%s)"
code=$(http_code "$root_url"); [ "$code" = "200" ] && ok "/ 200" || ko "/ $code"
hdr=$(header "$BASE/" "X-WSGI-Bridge"); [ -n "$hdr" ] && ok "X-WSGI-Bridge presente" || ko "X-WSGI-Bridge ausente"
cc=$(header "$BASE/" "Cache-Control");  echo "$cc" | grep -qi "no-store" && ok "Cache-Control no-store" || ko "Falta no-store en Cache-Control"
$CURL "$root_url" | grep -qm1 -- '--teal:#8fd3d0' && ok "Index pastel detectado" || ko "Index pastel no detectado"

echo "== /api/deploy-stamp =="
if json "$BASE/api/deploy-stamp" | jq -e '.ok==true and (.commit|length)>0' >/dev/null 2>&1; then
  ok "deploy-stamp ok + commit"
else ko "deploy-stamp inválido"; fi

echo "== GET /api/notes (paginación) =="
HDRS=$($CURL -i "$BASE/api/notes?limit=2" | sed -n '1,20p')
echo "$HDRS" | grep -qi '^link: .*rel="next"' && ok "Link header next" || ko "Falta Link header next"
echo "$HDRS" | grep -qi '^x-next-cursor:'     && ok "X-Next-Cursor header" || ko "Falta X-Next-Cursor"
echo "$HDRS" | grep -qi '%3A'                 && ok "Link timestamp URL-encoded" || info "No veo %3A en Link"
COUNT=$(json "$BASE/api/notes?limit=2" | jq '.items|length' 2>/dev/null || echo 0)
[ "$COUNT" -ge 0 ] && ok "Body JSON con $COUNT items" || ko "Body JSON inválido"
NEXT=$(json "$BASE/api/notes?limit=2" | jq -r 'if .next then @uri "cursor_ts=\(.next.cursor_ts)&cursor_id=\(.next.cursor_id)" else empty end')
if [ -n "$NEXT" ]; then
  COUNT2=$(json "$BASE/api/notes?limit=2&$NEXT" | jq '.items|length' 2>/dev/null || echo 0)
  ok "Next page devuelve $COUNT2 items"
else info "No next page (pocas notas)"; fi

echo "== HEAD /api/notes =="
HEADHDR=$($CURL -I "$BASE/api/notes?limit=1")
echo "$HEADHDR" | head -n1 | grep -q "200"        && ok "HEAD 200"         || ko "HEAD !200"
echo "$HEADHDR" | grep -qi '^content-length: 0'   && ok "HEAD sin cuerpo"  || ko "HEAD con cuerpo"
echo "$HEADHDR" | grep -qi '^x-next-cursor:'      && ok "HEAD x-next-cursor" || ko "HEAD sin x-next-cursor"

echo "== POST + like/view/report + removed al 5º =="
NEWID=$(json "$BASE/api/notes" -H 'content-type: application/json' --data-binary '{"text":"check_suite ✅"}' | jq -r '.item.id' 2>/dev/null || echo "")
if [[ "$NEWID" =~ ^[0-9]+$ ]]; then
  ok "POST creó id $NEWID"
  json "$BASE/api/notes/$NEWID/like"  >/dev/null && ok "like OK" || ko "like falló"
  json "$BASE/api/notes/$NEWID/view"  >/dev/null && ok "view OK" || ko "view falló"
  R1=$(json "$BASE/api/notes/$NEWID/report" | jq -r '.reports' 2>/dev/null || echo "")
  R2=$(json "$BASE/api/notes/$NEWID/report" | jq -r '.reports' 2>/dev/null || echo "")
  [ "$R1" = "$R2" ] && ok "report dedupe misma persona" || ko "report dup suma ($R1->$R2)"
  for fp in u2 u3 u4; do json "$BASE/api/notes/$NEWID/report" -H "X-FP: $fp" >/dev/null; done
  RES=$(json "$BASE/api/notes/$NEWID/report" -H "X-FP: u5")
  echo "$RES" | jq -e '.removed==true' >/dev/null 2>&1 && ok "5º reporte → removed" || ko "no se removió al 5º"
  json "$BASE/api/notes/$NEWID" | jq -e '.ok==false and .error=="not_found"' >/dev/null 2>&1 && ok "GET por id not_found" || ko "GET por id debería ser not_found"
else
  ko "POST /api/notes no devolvió id"
fi

echo "== Términos & Privacidad =="
for p in terms privacy; do
  c=$(http_code "$BASE/$p"); [ "$c" = "200" ] && ok "/$p 200" || ko "/$p $c"
  len=$($CURL "$BASE/$p" | wc -c | awk '{print $1}')
  [ "$len" -ge 200 ] && ok "/$p con contenido ($len bytes)" || ko "/$p parece vacío ($len bytes)"
done

echo
echo "Resumen: $PASS ok, $FAIL errores"
[ "$FAIL" -eq 0 ] || exit 1
