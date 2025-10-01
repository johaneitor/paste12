#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

ts() { date -u +%Y%m%d-%H%M%SZ; }
TS="$(ts)"
WORK="$HOME/.cache/p12/verify-$TS"
mkdir -p "$WORK" "$OUTDIR"
DEST_DIR="$OUTDIR/p12-verify-$TS"
mkdir -p "$DEST_DIR"

# curl helpers
hc() { sed -n '1p' "$1" | sed -E 's#HTTP/[^ ]+ ##'; } # first status line → code/text
curl_hb() {
  local url="$1"; shift
  local hdr="$WORK/hdr-$(basename "$1" .json)-$RANDOM.txt"
  local body="$WORK/body-$(basename "$1" .json)-$RANDOM.bin"
  local code
  code="$(curl -sS -D "$hdr" -o "$body" -w '%{http_code}' "$@" "$url")" || code="$?"
  echo "$hdr" "$body" "$code"
}

log(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$DEST_DIR/summary.tsv"; echo "• $1: $2 -> $3"; }
save(){ cp -f "$1" "$DEST_DIR/"; }

trap 'cp -f "$WORK"/* "$DEST_DIR/" 2>/dev/null || true' EXIT

echo -e "check\tendpoint\tresult" > "$DEST_DIR/summary.tsv"

echo "== POSITIVOS =="
# Index
read H B C < <(curl_hb "$BASE" "$WORK/idx.json")
save "$H"; save "$B"
[[ "$C" == 200 ]] && log "GET /" "/" "PASS" || log "GET /" "/" "FAIL($C)"

# Terms / Privacy (WSGI fallback)
for p in terms privacy; do
  read H B C < <(curl_hb "$BASE/$p" "$WORK/${p}.json")
  save "$H"; save "$B"
  [[ "$C" == 200 ]] && log "GET /$p" "/$p" "PASS" || log "GET /$p" "/$p" "FAIL($C)"
done

# Listado /api/notes
read H B C < <(curl_hb "$BASE/api/notes?limit=10" "$WORK/notes.json" -H 'Accept: application/json')
save "$H"; cp -f "$B" "$DEST_DIR/notes-page1.json"
if [[ "$C" == 200 ]] && grep -q '"id"' "$B"; then
  log "GET /api/notes?limit=10" "list" "PASS"
else
  log "GET /api/notes?limit=10" "list" "FAIL($C)"
fi

# Publicar por JSON
TXT_JSON="suite json $TS :: $(head -c 6 /dev/urandom | base64)"
read H B C < <(curl_hb "$BASE/api/notes" "$WORK/pub-json.json" \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"$TXT_JSON\",\"ttl_hours\":12}")
save "$H"; save "$B"
NEW_ID_JSON="$(python - <<PY
import json,sys,re
try:
  j=json.load(open("$B","rb"))
  print(j.get("id") or (j.get("item") or {}).get("id") or "")
except Exception: print("")
PY
)"
[[ -n "$NEW_ID_JSON" && "$C" =~ ^(200|201)$ ]] && log "POST /api/notes [json]" "create_json" "PASS(#$NEW_ID_JSON)" || log "POST /api/notes [json]" "create_json" "FAIL($C)"

# Publicar por FORM (fallback)
TXT_FORM="suite form $TS :: $(head -c 6 /dev/urandom | base64)"
read H B C < <(curl_hb "$BASE/api/notes" "$WORK/pub-form.json" \
  -H 'Accept: application/json' \
  --data-urlencode "text=$TXT_FORM" --data-urlencode "ttl_hours=12")
save "$H"; save "$B"
NEW_ID_FORM="$(python - <<PY
import json,sys
try:
  j=json.load(open("$B","rb"))
  print(j.get("id") or (j.get("item") or {}).get("id") or "")
except Exception: print("")
PY
)"
[[ -n "$NEW_ID_FORM" && "$C" =~ ^(200|201)$ ]] && log "POST /api/notes [form]" "create_form" "PASS(#$NEW_ID_FORM)" || log "POST /api/notes [form]" "create_form" "FAIL($C)"

# Like / View / Report sobre el creado por JSON (si existe)
ID="${NEW_ID_JSON:-}"
if [[ -n "$ID" ]]; then
  read H B C < <(curl_hb "$BASE/api/notes/$ID/like" "$WORK/like.json" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  if [[ "$C" == 200 ]] && grep -q '"likes"' "$B"; then log "POST like" "/api/notes/$ID/like" "PASS"
  else log "POST like" "/api/notes/$ID/like" "FAIL($C)"; fi

  read H B C < <(curl_hb "$BASE/api/notes/$ID/view" "$WORK/view.json" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  [[ "$C" == 200 ]] && log "POST view" "/api/notes/$ID/view" "PASS" || log "POST view" "/api/notes/$ID/view" "FAIL($C)"

  # Report no obliga a borrar; verificamos 200/202 + json
  read H B C < <(curl_hb "$BASE/api/notes/$ID/report" "$WORK/report.json" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  [[ "$C" =~ ^(200|202)$ ]] && log "POST report" "/api/notes/$ID/report" "PASS" || log "POST report" "/api/notes/$ID/report" "WARN($C)"
else
  log "like/view/report" "(sin id)" "SKIP"
fi

echo "== NEGATIVOS =="
for ep in like view report; do
  read H B C < <(curl_hb "$BASE/api/notes/99999999/$ep" "$WORK/neg-$ep.json" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  [[ "$C" == 404 ]] && log "NEG $ep" "/api/notes/99999999/$ep" "PASS(404)" || log "NEG $ep" "/api/notes/99999999/$ep" "FAIL($C)"
done

echo "== LIMITES =="
# 1) TTL borde: probar ttl_hours=0 y ttl_hours=0.05 (si acepta floats); se considera PASS si rechaza 0 o acepta 0.05
read H B C < <(curl_hb "$BASE/api/notes" "$WORK/ttl0.json" \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"ttl0 $TS\",\"ttl_hours\":0}")
save "$H"; save "$B"
if [[ "$C" =~ ^(400|422)$ ]]; then
  log "TTL check" "ttl_hours=0" "PASS(rechazado:$C)"
else
  # intento con decimal corto
  read H2 B2 C2 < <(curl_hb "$BASE/api/notes" "$WORK/ttldec.json" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data "{\"text\":\"ttldec $TS\",\"ttl_hours\":0.05}")
  save "$H2"; save "$B2"
  if [[ "$C2" =~ ^(200|201)$ ]]; then
    log "TTL check" "ttl_hours=0.05" "PASS(aceptado:$C2)"
  else
    log "TTL check" "0/0.05" "SOFT($C,$C2)"
  fi
fi

# 2) Paginación y Link rel=next (capacidad visible)
read H B C < <(curl_hb "$BASE/api/notes?limit=10" "$WORK/page1.json" -H 'Accept: application/json')
save "$H"; save "$B"
NEXT="$(grep -i '^Link:' "$H" | sed -n 's/.*<\([^>]*\)>\s*;\s*rel="?next"?/\1/p' | head -1)"
if [[ -n "$NEXT" ]]; then
  log "Paginación" "Link rel=next" "PASS"
else
  # intento por X-Next-Cursor JSON
  XN="$(python - <<PY
import json,sys
try:
  import base64
  print(json.loads(open("$H","rb").read().decode(errors="ignore").split("X-Next-Cursor:",1)[1].splitlines()[0].strip()))
except Exception: print("")
PY
)"
  [[ -n "$XN" ]] && log "Paginación" "X-Next-Cursor" "PASS" || log "Paginación" "next" "SOFT(no header)"
fi

# 3) Presión de capacidad: crear N=40 notas y observar si IDs viejos dejan de aparecer en ventana de 200
N="${N_NOTES_PRESSURE:-40}"
CREATED=""
for i in $(seq 1 $N); do
  read _ _ Cx < <(curl_hb "$BASE/api/notes" "$WORK/bulk-$i.json" \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data "{\"text\":\"bulk $TS #$i\",\"ttl_hours\":12}")
  [[ "$Cx" =~ ^(200|201)$ ]] || true
done
# juntar hasta 200 items y contar únicos
python - "$BASE" "$DEST_DIR/capacity-snapshot.json" <<'PY'
import json,sys,urllib.request
base=sys.argv[1]; out=sys.argv[2]
items=[]
url=f"{base}/api/notes?limit=50"
seen=set()
for _ in range(6): # hasta ~300
    try:
        r=urllib.request.urlopen(urllib.request.Request(url,headers={'Accept':'application/json'}),timeout=10)
        j=json.load(r)
        chunk=j if isinstance(j,list) else j.get('items',[])
        for it in chunk:
            if str(it.get('id')) not in seen:
                items.append(it); seen.add(str(it.get('id')))
        # parse Link header (simple)
        link=r.headers.get('Link') or r.headers.get('link')
        if link and 'rel="next"' in link:
            import re
            m=re.search(r'<([^>]+)>\s*;\s*rel="?next"?', link, re.I)
            if m: url=m.group(1); continue
        break
    except Exception as e:
        break
open(out,'w').write(json.dumps({'count':len(items),'ids':[it.get('id') for it in items]},ensure_ascii=False,indent=2))
print(len(items))
PY
CNT=$?
if [[ "$CNT" -gt 0 ]]; then
  log "Capacidad (ventana)" "ids_cosechados" "OBS($(cat "$DEST_DIR/capacity-snapshot.json" | wc -c)B-json)"
else
  log "Capacidad (ventana)" "fetch" "SKIP"
fi

echo "== NEGATIVOS (reassert) =="
# Reafirmar con endpoints "cortos"
for ep in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/notes/99999999/$ep")"
  [[ "$code" == "404" ]] && log "NEG $ep (re)" "…" "PASS(404)" || log "NEG $ep (re)" "…" "FAIL($code)"
done

echo "OK: reporte en $DEST_DIR"
