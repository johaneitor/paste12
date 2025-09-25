#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-}"
OUT="${2:-/sdcard/Download}"
CID="${3:-}"  # opcional: ca-pub-XXXX

if [[ -z "$BASE" ]]; then
  echo "Uso: $0 BASE [OUT_dir=/sdcard/Download] [ADSENSE_CLIENT_ID]"
  exit 1
fi

# Termux storage (si hiciera falta)
if [[ "$OUT" == /sdcard/* ]] && [[ ! -d "$OUT" ]]; then
  echo "⚠ OUT=$OUT no existe. Si usas Termux, corre: termux-setup-storage"
  mkdir -p "$OUT" || true
fi

TS="$(date -u +%Y%m%d-%H%M%SZ)"
F1="$OUT/01-backend-$TS.txt"
F2="$OUT/02-api-notes-$TS.txt"
F3="$OUT/03-frontend-index-$TS.txt"
F4="$OUT/04-terms-privacy-$TS.txt"
F5="$OUT/05-adsense-everywhere-$TS.txt"
F6="$OUT/06-summary-$TS.txt"

TMPD="$(mktemp -d)"
cleanup(){ rm -rf "$TMPD"; }
trap cleanup EXIT

writeln() { printf "%s\n" "$*" >> "$1"; }
hdr() { printf "\n==== %s ====\n" "$*" >> "$1"; }

########################################
# 01 - Backend (health + OPTIONS)
########################################
hdr "$F1" "BACKEND AUDIT (health + headers)"
writeln "$F1" "[base] $BASE"
writeln "$F1" "[ts]   $TS"

HEALTH_JSON="$TMPD/health.json"
if curl -sS "$BASE/api/health" -o "$HEALTH_JSON"; then
  writeln "$F1" "-- /api/health --"
  cat "$HEALTH_JSON" >> "$F1"
else
  writeln "$F1" "-- /api/health -- ERROR"
fi

hdr "$F1" "OPTIONS /api/notes"
curl -sS -i -X OPTIONS "$BASE/api/notes" >> "$F1" || true

########################################
# 02 - /api/notes (headers + body + Link)
########################################
hdr "$F2" "GET /api/notes (headers)"
API_H="$TMPD/api-h.txt"
API_B="$TMPD/api-b.json"
if curl -sS -D "$API_H" -o "$API_B" "$BASE/api/notes?limit=10"; then
  cat "$API_H" >> "$F2"
  hdr "$F2" "Body (primeras 2 líneas)"
  head -n 2 "$API_B" >> "$F2" || true
else
  writeln "$F2" "ERROR al hacer GET /api/notes?limit=10"
fi

# Link header
LINK_LINE="$(grep -i '^link:' "$API_H" || true)"
hdr "$F2" "Link header"
[[ -n "$LINK_LINE" ]] && writeln "$F2" "$LINK_LINE" || writeln "$F2" "NO LINK HEADER"

########################################
# 03 - index.html (headers + checks)
########################################
IDX_H="$TMPD/index.h"
IDX_B="$TMPD/index.html"
curl -sS -D "$IDX_H" -o "$IDX_B" "$BASE/" || true

hdr "$F3" "GET / (headers)"
cat "$IDX_H" >> "$F3" || true

hdr "$F3" "Checks index (adsense, views, hotfix, títulos)"
python - <<'PY' >> "$F3"
import re,sys,hashlib,io,os
p=os.environ.get("IDX_B")
b=io.open(p,"r",encoding="utf-8",errors="ignore").read() if p and os.path.exists(p) else ""
def yesno(x): return "OK" if x else "FAIL"

ads_meta = re.search(r'<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']', b, re.I)
ads_script = re.search(r'<script[^>]+pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=([^"&\']+)', b, re.I)
views = re.search(r'<span[^>]+class=["\']?views\b', b, re.I)
hotfix = re.search(r'hotfix\s*v4', b, re.I)
h1 = len(re.findall(r'<h1\b', b, re.I))
h2 = len(re.findall(r'<h2\b', b, re.I))

print(f"AdSense meta: {yesno(bool(ads_meta))}  value={ads_meta.group(1) if ads_meta else '-'}")
print(f"AdSense script: {yesno(bool(ads_script))}  client={ads_script.group(1) if ads_script else '-'}")
print(f"Views <span class='views'>: {yesno(bool(views))}")
print(f"Hotfix v4 marker: {yesno(bool(hotfix))}")
print(f"<h1> count: {h1}  <h2> count: {h2}")
if h1>1 or h2>1:
  print("WARN: Títulos duplicados detectados (revisar deduplicación).")
sh=hashlib.sha256(b.encode("utf-8")).hexdigest() if b else "-"
print(f"sha256(live index.html): {sh}")
PY
PY
########################################
# 04 - /terms y /privacy (headers + checks)
########################################
for P in terms privacy; do
  HDR="$TMPD/${P}.h"
  BODY="$TMPD/${P}.html"
  curl -sS -D "$HDR" -o "$BODY" "$BASE/$P" || true
  hdr "$F4" "GET /$P (headers)"
  cat "$HDR" >> "$F4" || true
  echo "" >> "$F4"
done

########################################
# 05 - AdSense everywhere (/, /terms, /privacy)
########################################
hdr "$F5" "AdSense everywhere (/ /terms /privacy)"
python - <<'PY' >> "$F5"
import re,io,os,sys
base=os.environ.get("BASE")
cid=os.environ.get("CID","").strip()
pages=["","terms","privacy"]
def analyze(text):
    head = bool(re.search(r'<head\b', text, re.I))
    m = re.search(r'<meta\s+name=["\']google-adsense-account["\']\s+content=["\']([^"\']+)["\']', text, re.I)
    s = re.search(r'<script[^>]+pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=([^"&\']+)', text, re.I)
    return head, (m.group(1) if m else ""), (s.group(1) if s else "")

for pg in pages:
    url = base + ("/"+pg if pg else "/")
    path = os.path.join(os.environ["TMPD"], ("index" if not pg else pg)+".html")
    txt = io.open(path,"r",encoding="utf-8",errors="ignore").read() if os.path.exists(path) else ""
    head, meta, script = analyze(txt)
    ok_head = "HEAD:1" if head else "HEAD:0"
    ok_tag  = "TAG:1" if script else "TAG:0"
    ok_cid  = "CID:?"; 
    if cid:
        ok_cid = "CID:1" if (meta==cid or script==cid) else "CID:0"
    print(f"-- /{pg if pg else ''} --  {ok_head} {ok_tag} {ok_cid}   url:{url}")
PY
PY
########################################
# 06 - SUMMARY priorizado
########################################
hdr "$F6" "SUMMARY (priorizado)"
python - <<'PY' >> "$F6"
import re,io,os,json

def load(p):
    try: return io.open(p,"r",encoding="utf-8",errors="ignore").read()
    except: return ""

base = os.environ.get("BASE")
tmpd = os.environ.get("TMPD")
cid  = os.environ.get("CID") or ""

health = load(os.path.join(tmpd,"health.json"))
idx    = load(os.path.join(tmpd,"index.html"))
idx_h  = load(os.path.join(tmpd,"index.h"))
terms  = load(os.path.join(tmpd,"terms.html"))
priv   = load(os.path.join(tmpd,"privacy.html"))
api_h  = load(os.path.join(tmpd,"api-h.txt"))

def has(pattern, s): return bool(re.search(pattern, s, re.I))

issues=[]

# Backend
if not has(r'"ok"\s*:\s*true', health):
    issues.append("[CRÍTICO] /api/health no OK (ver #01).")
if not has(r'Access-Control-Allow-Origin:\s*\*', load(os.path.join(tmpd,"api-h.txt"))):
    issues.append("[ALTA] Falta ACAO en /api/notes (CORS).")

# API notes headers/body
if not has(r'^Link:\s*<.+rel="next"', load(os.path.join(tmpd,"api-h.txt"))):
    issues.append("[MEDIA] Falta/irregular Link header en /api/notes (paginación).")

# Frontend index
if not has(r'<span[^>]+class=["\']?views\b', idx):
    issues.append("[ALTA] Falta <span class=\"views\"> en index (métricas).")

if not has(r'google-adsense-account', idx):
    issues.append("[ALTA] Falta meta AdSense en <head> del index.")

if len(re.findall(r'<h1\b', idx, re.I))>1 or len(re.findall(r'<h2\b', idx, re.I))>1:
    issues.append("[MEDIA] Títulos/subtítulos duplicados (limpiar deduplicación).")

# Legales
if not terms:
    issues.append("[MEDIA] /terms no disponible o vacío.")
if not priv:
    issues.append("[MEDIA] /privacy no disponible o vacío.")

# Resultado
if not issues:
    print("OK: sin hallazgos críticos. Recomendaciones menores: mantener auditorías periódicas.")
else:
    for i, it in enumerate(issues, 1):
        print(f"{i}. {it}")

print("\nSugerencias de remediación (orden):")
print("  1) Asegurar /api/health y /api/notes 200 + CORS + Link header.")
print("  2) En index: insertar <meta name=\"google-adsense-account\" ...> y script pagead(...client=...).")
print("  3) Asegurar <span class=\"views\"> y remover duplicados de <h1>/<h2>.")
print("  4) Verificar /terms y /privacy 200 (+ AdSense si aplica).")
print("  5) Correr compare live vs repo y hacer deploy con cache-bust.")
PY
PY

echo "Guardados:"
printf "  %s\n  %s\n  %s\n  %s\n  %s\n  %s\n" "$F1" "$F2" "$F3" "$F4" "$F5" "$F6"
