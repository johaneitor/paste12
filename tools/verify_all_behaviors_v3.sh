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

sanitize(){ echo "$1" | sed 's#[^a-zA-Z0-9._-]#_#g'; }
join(){ local a="${1%/}"; local b="${2#/}"; echo "$a/$b"; }
curl_hb(){ # URL LABEL [extra curl args...]
  local url="$1"; local lbl="$(sanitize "$2")"; shift 2
  local hdr="$WORK/hdr-${lbl}.txt"; local body="$WORK/body-${lbl}.bin"
  local code
  code="$(curl -sS -D "$hdr" -o "$body" -w '%{http_code}' "$@" "$url" || true)"
  echo "$hdr" "$body" "$code"
}
json_get_id(){
  python - <<'PY' "$1"
import sys,json
try:
  j=json.load(open(sys.argv[1],'rb'))
  print(j.get('id') or (j.get('item') or {}).get('id') or '')
except Exception:
  print('')
PY
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

# -----------------------------
# POSITIVOS BÁSICOS
# -----------------------------
say "== POSITIVOS =="
read H B C < <(curl_hb "$(join "$BASE" "/")" idx)
save "$H"; save "$B"; [[ "$C" == 200 ]] && log "GET /" "/" "PASS" || log "GET /" "/" "FAIL($C)"

for p in terms privacy; do
  read H B C < <(curl_hb "$(join "$BASE" "/$p")" "$p")
  save "$H"; save "$B"
  [[ "$C" == 200 ]] && log "GET /$p" "/$p" "PASS" || log "GET /$p" "/$p" "FAIL($C)"
done

read H B C < <(curl_hb "$(join "$BASE" "/api/notes?limit=10")" "notes_p1" -H 'Accept: application/json')
save "$H"; cp -f "$B" "$DEST_DIR/notes-page1.json" 2>/dev/null || true
if [[ "$C" == 200 ]] && [[ "$(exists_json_key "$B" id)" == "1" ]]; then
  log "GET /api/notes?limit=10" "list" "PASS"
else
  log "GET /api/notes?limit=10" "list" "FAIL($C)"
fi

# -----------------------------
# CREATE (JSON / FORM) con diagnóstico de 405
# -----------------------------
post_variants=(
  "/api/notes|json"
  "/api/notes|form"
  "/api/note|json"
  "/api/note|form"
  "/api/notes/create|json"
  "/api/notes/create|form"
)

NEW_ID_JSON=""
TXT_JSON="suite json $TS :: $(head -c 6 /dev/urandom | base64)"
for v in "${post_variants[@]}"; do
  ep="${v%%|*}"; mode="${v##*|}"
  lbl="create_${mode}_$(sanitize "$ep")"
  if [[ "$mode" == "json" ]]; then
    read H B C < <(curl_hb "$(join "$BASE" "$ep")" "$lbl" -X POST \
      -H 'Content-Type: application/json' -H 'Accept: application/json' \
      --data "{\"text\":\"$TXT_JSON\",\"ttl_hours\":12}")
  else
    read H B C < <(curl_hb "$(join "$BASE" "$ep")" "$lbl" -X POST \
      -H 'Accept: application/json' \
      --data-urlencode "text=$TXT_JSON" --data-urlencode "ttl_hours=12")
  fi
  save "$H"; save "$B"
  allow="$(grep -i '^Allow:' "$H" | sed 's/\r//')"
  id="$(json_get_id "$B")"
  [[ "$ep" == "/api/notes" && "$mode" == "json" ]] && base_lbl="POST /api/notes [json]" || base_lbl="POST $ep [$mode]"
  if [[ -n "$id" && "$C" =~ ^(200|201)$ ]]; then
    log "$base_lbl" "$ep" "PASS(#$id)"
    [[ -z "$NEW_ID_JSON" ]] && NEW_ID_JSON="$id"
  else
    msg="FAIL($C"; [[ -n "$allow" ]] && msg="$msg, Allow: ${allow#Allow: }"; msg="$msg)"
    log "$base_lbl" "$ep" "$msg"
  fi
done

# -----------------------------
# like/view/report sobre el creado (si hay id)
# -----------------------------
API_ACT(){
  local the_id="$1"; local act="$2"
  # 1) REST POST
  read H B C < <(curl_hb "$(join "$BASE" "/api/notes/$the_id/$act")" "act_${act}_${the_id}_rest" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"; [[ "$C" =~ ^(200|202)$ ]] && { echo "$C"; return 0; }
  # 2) Legacy POST
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$the_id")" "act_${act}_${the_id}_legacy_p" -X POST -H 'Accept: application/json')
  save "$H"; save "$B"; [[ "$C" =~ ^(200|202)$ ]] && { echo "$C"; return 0; }
  # 3) Legacy GET
  read H B C < <(curl_hb "$(join "$BASE" "/api/$act?id=$the_id")" "act_${act}_${the_id}_legacy_g" -H 'Accept: application/json')
  save "$H"; save "$B"; echo "$C"; return 1
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

# -----------------------------
# NEGATIVOS (IDs inexistentes → 404)
# -----------------------------
say "== NEGATIVOS =="
NEG(){
  local act="$1"; local bad="99999999"
  # evitemos el bug nounset: declarar por separado
  local rest="/api/notes/${bad}/${act}"
  local legacy="/api/${act}?id=${bad}"

  read H B C < <(curl_hb "$(join "$BASE" "$rest")" "neg_rest_${act}" -X POST -H 'Accept: application/json'); save "$H"; save "$B"
  [[ "$C" == 404 ]] && { echo 404; return 0; }

  read H B C < <(curl_hb "$(join "$BASE" "$legacy")" "neg_leg_p_${act}" -X POST -H 'Accept: application/json'); save "$H"; save "$B"
  [[ "$C" == 404 ]] && { echo 404; return 0; }

  read H B C < <(curl_hb "$(join "$BASE" "$legacy")" "neg_leg_g_${act}" -H 'Accept: application/json'); save "$H"; save "$B"
  echo "$C"
}
for act in like view report; do
  code="$(NEG "$act")"
  [[ "$code" == 404 ]] && log "NEG $act" "$act(99999999)" "PASS(404)" || log "NEG $act" "$act(99999999)" "FAIL($code)"
done

# -----------------------------
# LIMITES (TTL, paginación, capacidad)
# -----------------------------
say "== LIMITES =="
# TTL = 0 (rechazo esperado) o tolerancia a decimal chico
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

# Paginación
read H B C < <(curl_hb "$(join "$BASE" "/api/notes?limit=10")" "page1" -H 'Accept: application/json')
save "$H"; save "$B"
NEXT="$(grep -i '^Link:' "$H" | sed -n 's/.*<\([^>]*\)>\s*;\s*rel="?next"?/\1/p' | head -1)"
[[ -n "$NEXT" ]] && log "Paginación" "Link rel=next" "PASS" || log "Paginación" "next" "SOFT(no header)"

# Presión de capacidad (40 items) y snapshot
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
CAP_COUNT="$(python - <<'PY'
import json,sys
try: print(json.load(open(sys.argv[1],'rb')).get('count','?'))
except: print('?')
PY
"$DEST_DIR/capacity-snapshot.json")"
log "Capacidad (ventana)" "colectados" "OBS(${CAP_COUNT})"

# TTL rápido (si lo permite)
FAST_MIN="${FAST_TTL_MINUTES:-3}"
read H B C < <(curl_hb "$(join "$BASE" "/api/notes")" "ttl_fast_create" \
  -X POST -H 'Content-Type: application/json' -H 'Accept: application/json' \
  --data "{\"text\":\"ttlfast $TS\",\"ttl_hours\":0.03}")
save "$H"; save "$B"
FAST_ID="$(json_get_id "$B")"
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

# README
cat > "$DEST_DIR/README.txt" <<TXT
p12 verify (v3) @ $TS
BASE: $BASE
Archivos:
- summary.tsv (tabla PASS/FAIL/WARN/SOFT/OBS/SKIP)
- notes-page1.json, capacity-snapshot.json
- hdr-*.txt (headers crudos), body-*.bin (bodies crudos)
TXT

echo "OK: reporte en $DEST_DIR"
