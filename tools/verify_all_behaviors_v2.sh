#!/usr/bin/env bash
set -euo pipefail
BASE="${1:?Uso: $0 BASE_URL [OUTDIR] }"
OUTDIR="${2:-/sdcard/Download}"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
WORK="$HOME/.cache/p12/verify-$TS"
DEST_DIR="$OUTDIR/p12-verify-$TS"
mkdir -p "$WORK" "$DEST_DIR"

echo -e "check\tendpoint\tresult" > "$DEST_DIR/summary.tsv"
say(){ echo "• $*"; }
log(){ printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$DEST_DIR/summary.tsv"; say "$1: $2 -> $3"; }
save(){ [[ -f "$1" ]] && cp -f "$1" "$DEST_DIR/" || true; }

# --- helpers ---
sanitize(){ echo "$1" | sed 's#[^a-zA-Z0-9._-]#_#g'; }
join(){ local a="$1" b="$2"; a="${a%/}"; b="${b#/}"; echo "$a/$b"; }
curl_hb(){ # URL LABEL [extra curl args...]
  local url="$1"; local lbl="$(sanitize "$2")"; shift 2
  local hdr="$WORK/hdr-${lbl}.txt"; local body="$WORK/body-${lbl}.bin"
  local code
  code="$(curl -sS -D "$hdr" -o "$body" -w '%{http_code}' "$@" "$url" || true)"
  echo "$hdr" "$body" "$code"
}
exists_json_key(){ local f="$1" k="$2"; python - "$f" "$k" <<'PY' || true
import sys,json
try:
  d=json.load(open(sys.argv[1],'rb'))
  k=sys.argv[2]
  def has(o,k):
    return (isinstance(o,dict) and k in o) or (isinstance(o,list) and any(has(x,k) for x in o))
  print("1" if has(d,k) else "0")
except Exception: print("0")
PY
}

# --- POSITIVOS ---
say "== POSITIVOS =="
read H B C < <(curl_hb "$(join "$BASE" "/")" idx)
save "$H"; save "$B"; [[ "$C" == 200 ]] && log "GET /" "/" "PASS" || log "GET /" "/" "FAIL($C)"

for p in terms privacy; do
  read H B C < <(curl_hb "$(join "$BASE" "/$p")" "$p")
  save "$H"; save "$B"; [[ "$C" == 200 ]] && log "GET /$p" "/$p" "PASS" || log "GET /$p" "/$p" "FAIL($C)"
done

read H B C < <(curl_hb "$(join "$BASE" "/api/notes?limit=10")" "notes_p1" -H 'Accept: application/json')
save "$H"; cp -f "$B" "$DEST_DIR/notes-page1.json" 2>/dev/null || true
if [[ "$C" == 200 ]] && [[ "$(exists_json_key "$B" id)" == "1" ]]; then
  log "GET /api/notes?limit=10" "list" "PASS"
else
  log "GET /api/notes?limit=10" "list" "FAIL($C)"
fi

TXT_JSON="suite json $TS :: $(head -c 6 /dev/urandom | base64)"
read H B C < <(curl_hb "$(join "$BASE" "/api/notes")" "create_json" \
  -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"$TXT_JSON\",\"ttl_hours\":12}")
save "$H"; save "$B"
NEW_ID_JSON="$(python - "$B" <<'PY'
import sys,json
try:
  j=json.load(open(sys.argv[1],'rb'))
  print(j.get('id') or (j.get('item') or {}).get('id') or '')
except Exception: print('')
PY
)"
[[ -n "$NEW_ID_JSON" && "$C" =~ ^(200|201)$ ]] && log "POST /api/notes [json]" "create_json" "PASS(#$NEW_ID_JSON)" || log "POST /api/notes [json]" "create_json" "FAIL($C)"

TXT_FORM="suite form $TS :: $(head -c 6 /dev/urandom | base64)"
read H B C < <(curl_hb "$(join "$BASE" "/api/notes")" "create_form" \
  -X POST -H 'Accept: application/json' --data-urlencode "text=$TXT_FORM" --data-urlencode "ttl_hours=12")
save "$H"; save "$B"
NEW_ID_FORM="$(python - "$B" <<'PY'
import sys,json
try:
  j=json.load(open(sys.argv[1],'rb')); print(j.get('id') or (j.get('item') or {}).get('id') or '')
except Exception: print('')
PY
)"
[[ -n "$NEW_ID_FORM" && "$C" =~ ^(200|201)$ ]] && log "POST /api/notes [form]" "create_form" "PASS(#$NEW_ID_FORM)" || log "POST /api/notes [form]" "create_form" "FAIL($C)"

# like/view/report contra el creado por JSON (si existe)
API_ACT(){
  local id="$1" act="$2" lbl="act_${act}_${id}"
  # 1) REST POST /api/notes/:id/:act
  read H B C < <(curl_hb "$(join "$BASE" "/api/notes/$id/$act")" "$lbl" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  if [[ "$C" =~ ^(200|202)$ ]]; then echo "$C"; return 0; fi
  # 2) Legacy POST /api/:act?id=
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$id")" "${lbl}_legacy_post" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"
  if [[ "$C" =~ ^(200|202)$ ]]; then echo "$C"; return 0; fi
  # 3) Legacy GET /api/:act?id=
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$id")" "${lbl}_legacy_get" -H 'Accept: application/json')
  save "$H"; save "$B"
  echo "$C"; return 1
}

if [[ -n "${NEW_ID_JSON:-}" ]]; then
  for act in like view report; do
    code="$(API_ACT "$NEW_ID_JSON" "$act")"
    if [[ "$act" == "report" ]]; then
      [[ "$code" =~ ^(200|202)$ ]] && log "POST $act" "$act/$NEW_ID_JSON" "PASS" || log "POST $act" "$act/$NEW_ID_JSON" "WARN($code)"
    else
      [[ "$code" == "200" ]] && log "POST $act" "$act/$NEW_ID_JSON" "PASS" || log "POST $act" "$act/$NEW_ID_JSON" "FAIL($code)"
    fi
  done
else
  log "like/view/report" "(sin id)" "SKIP"
fi

# --- NEGATIVOS ---
say "== NEGATIVOS =="
NEG(){
  local act="$1" id="99999999" base="/api/notes/$id/$act"
  # REST
  read H B C < <(curl_hb "$(join "$BASE" "$base")" "neg_rest_${act}" -X POST -H 'Accept: application/json'); save "$H"; save "$B"
  [[ "$C" == 404 ]] && { echo 404; return 0; }
  # Legacy POST
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$id")" "neg_leg_p_${act}" -X POST -H 'Accept: application/json'); save "$H"; save "$B"
  [[ "$C" == 404 ]] && { echo 404; return 0; }
  # Legacy GET
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$id")" "neg_leg_g_${act}" -H 'Accept: application/json'); save "$H"; save "$B"
  echo "$C"
}
for act in like view report; do
  code="$(NEG "$act")"
  [[ "$code" == 404 ]] && log "NEG $act" "$act(99999999)" "PASS(404)" || log "NEG $act" "$act(99999999)" "FAIL($code)"
done

# --- LIMITES ---
say "== LIMITES =="

# TTL borde (0 debe rechazar o aceptar decimal chico)
read H B C < <(curl_hb "$(join "$BASE" "/api/notes")" "ttl0" \
  -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"ttl0 $TS\",\"ttl_hours\":0}")
save "$H"; save "$B"
if [[ "$C" =~ ^(400|422)$ ]]; then
  log "TTL" "ttl_hours=0" "PASS(rechazado:$C)"
else
  read H2 B2 C2 < <(curl_hb "$(join "$BASE" "/api/notes")" "ttldec" \
    -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data "{\"text\":\"ttldec $TS\",\"ttl_hours\":0.05}")
  save "$H2"; save "$B2"
  if [[ "$C2" =~ ^(200|201)$ ]]; then log "TTL" "ttl_hours=0.05" "PASS(aceptado:$C2)"
  else log "TTL" "0/0.05" "SOFT($C,$C2)"; fi
fi

# Paginación / Link rel=next
read H B C < <(curl_hb "$(join "$BASE" "/api/notes?limit=10")" "page1" -H 'Accept: application/json')
save "$H"; save "$B"
NEXT="$(grep -i '^Link:' "$H" | sed -n 's/.*<\([^>]*\)>\s*;\s*rel="?next"?/\1/p' | head -1)"
[[ -n "$NEXT" ]] && log "Paginación" "Link rel=next" "PASS" || log "Paginación" "next" "SOFT(no header)"

# Presión de capacidad (40 items) y observación de ventana
N="${N_NOTES_PRESSURE:-40}"
for i in $(seq 1 $N); do
  curl -sS -o /dev/null -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
    --data "{\"text\":\"bulk $TS #$i\",\"ttl_hours\":12}" "$(join "$BASE" "/api/notes")" || true
done
python - "$BASE" "$DEST_DIR/capacity-snapshot.json" <<'PY'
import json,sys,urllib.request,re
base=sys.argv[1]; out=sys.argv[2]
items=[]; url=f"{base}/api/notes?limit=50"; seen=set()
for _ in range(6):
  try:
    r=urllib.request.urlopen(urllib.request.Request(url,headers={'Accept':'application/json'}),timeout=10)
    j=json.load(r)
    chunk=j if isinstance(j,list) else j.get('items',[])
    for it in chunk:
      sid=str(it.get('id')); 
      if sid not in seen: seen.add(sid); items.append(it)
    link=r.headers.get('Link') or r.headers.get('link')
    m=re.search(r'<([^>]+)>\s*;\s*rel="?next"?', link or '', re.I)
    if m: url=m.group(1); continue
    break
  except Exception: break
open(out,'w').write(json.dumps({'count':len(items),'ids':[it.get('id') for it in items]},ensure_ascii=False,indent=2))
print(len(items))
PY
log "Capacidad (ventana)" "colectados" "OBS($(jq -r '.count' "$DEST_DIR/capacity-snapshot.json" 2>/dev/null || echo '?'))"

# TTL expiración rápida (si el backend permite <0.05 h ≈ 3 min)
FAST_MIN="${FAST_TTL_MINUTES:-3}"
read H B C < <(curl_hb "$(join "$BASE" "/api/notes")" "ttl_fast_create" \
  -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"ttlfast $TS\",\"ttl_hours\":0.03}")
save "$H"; save "$B"
FAST_ID="$(python - "$B" <<'PY'
import sys,json
try:
  j=json.load(open(sys.argv[1],'rb')); print(j.get('id') or (j.get('item') or {}).get('id') or '')
except Exception: print('')
PY
)"
if [[ -n "$FAST_ID" && "$C" =~ ^(200|201)$ ]]; then
  say "Esperando expiración (~${FAST_MIN}m máx)…"
  end=$(( $(date +%s) + FAST_MIN*60 ))
  expired="NO"
  while (( $(date +%s) < end )); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$(join "$BASE" "/api/notes/$FAST_ID")" || true)"
    if [[ "$code" == "404" ]]; then expired="SI"; break; fi
    sleep 15
  done
  log "TTL expiración" "id=$FAST_ID" "OBS(expired=${expired})"
else
  log "TTL expiración" "id=(n/a)" "SKIP"
fi

# Reafirmar negativos tras presión
for act in like view report; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$(join "$BASE" "/api/notes/99999999/$act")" || true)"
  [[ "$code" == "404" ]] || code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$(join "$BASE" "/api/$act?id=99999999")" || true)"
  [[ "$code" == "404" ]] && log "NEG $act (re)" "…" "PASS(404)" || log "NEG $act (re)" "…" "FAIL($code)"
done

# README
cat > "$DEST_DIR/README.txt" <<TXT
p12 verify (v2) @ $TS
BASE: $BASE
Archivos:
- summary.tsv (tabla PASS/FAIL/SOFT/OBS/SKIP)
- notes-page1.json, capacity-snapshot.json
- hdr-*.txt (headers), body-*.bin (respuestas)
TXT

echo "OK: reporte en $DEST_DIR"
