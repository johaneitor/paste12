#!/usr/bin/env bash
set -euo pipefail

BASE="${1:-https://paste12-rmsk.onrender.com}"
OUTDIR="${2:-/sdcard/Download}"

# Requisitos mínimos: curl, python
command -v curl >/dev/null || { echo "ERROR: falta 'curl'"; exit 2; }
command -v python >/dev/null || command -v python3 >/dev/null || { echo "ERROR: falta 'python'"; exit 2; }
PYBIN="$(command -v python || command -v python3)"

TS="$(date -u +%Y%m%d-%H%M%SZ)"
mkdir -p "$OUTDIR" .tmp >/dev/null 2>&1 || true

LIVE_HTML="$OUTDIR/index-live-$TS.html"
LOCAL_HTML="$OUTDIR/index-local-$TS.html"
REPORT="$OUTDIR/frontend-live-audit-$TS.txt"
HDRS="$OUTDIR/api-notes-headers-$TS.txt"
HEALTH="$OUTDIR/health-$TS.json"

echo "[i] BASE = $BASE"
echo "[i] OUT  = $OUTDIR"
echo "[i] ts   = $TS"

# 1) Descarga HTML en vivo (rompiendo caché y SW si existiera)
curl -fsSL "$BASE/?debug=1&nosw=1&v=$TS" -o "$LIVE_HTML" || { echo "ERROR: no pude descargar $BASE"; exit 3; }
[[ -s "$LIVE_HTML" ]] || { echo "ERROR: HTML remoto vacío"; exit 3; }

# 2) Local: intenta ubicar el index del repo
LOC_CANDIDATES=(frontend/index.html web/index.html index.html)
FOUND_LOCAL=""
for p in "${LOC_CANDIDATES[@]}"; do
  if [[ -f "$p" ]]; then
    cp -f "$p" "$LOCAL_HTML"
    FOUND_LOCAL="$p"
    break
  fi
done
if [[ -z "$FOUND_LOCAL" ]]; then
  echo "<!-- no-local -->" > "$LOCAL_HTML"
fi

# 3) Headers de /api/notes y /api/health
curl -fsSI "$BASE/api/notes?limit=10" > "$HDRS" || true
curl -fsSL "$BASE/api/health" -o "$HEALTH" || true

# 4) Análisis y reporte (Python para expresividad y robustez)
"$PYBIN" - <<PY
import hashlib, re, io, os, sys

base = "$BASE"
live_path = "$LIVE_HTML"
loc_path  = "$LOCAL_HTML"
hdrs_path = "$HDRS"
rep_path  = "$REPORT"

def readf(p):
    try:
        return io.open(p, "r", encoding="utf-8", errors="ignore").read()
    except Exception:
        return ""

live = readf(live_path)
loc  = readf(loc_path)
hdrs = readf(hdrs_path)

def sha(s): return hashlib.sha256(s.encode("utf-8")).hexdigest()
def present(rx, s, flags=re.I|re.S): return re.search(rx, s, flags) is not None

report=[]
report.append("== Frontend Live Deep Audit v2 ==")
report.append(f"BASE: {base}")
report.append(f"live_sha : {sha(live)}")
report.append(f"local_sha: {sha(loc)}")
report.append(f"local_src: {'(none)' if '<!-- no-local -->' in loc else '$FOUND_LOCAL'}")

# ---- Chequeos Live ----
live_checks = [
    ("views span (.views)", present(r'<span[^>]*class=["\\\']views["\\\']', live)),
    ("AdSense", "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" in live),
    ("duplicated subtitle (<h2> >1)", len(re.findall(r'<h2[^>]*>', live, re.I)) > 1),
    ("service worker refs", present(r'serviceWorker\\s*\\.', live)),
    ("summary-enhancer marker", ("summary-enhancer" in live) or ("p12-summary" in live)),
    ("hotfix v4 marker", "p12-hotfix-v4" in live),
    ("footer: /terms", present(r'href=["\\\']/terms["\\\']', live)),
    ("footer: /privacy", present(r'href=["\\\']/privacy["\\\']', live)),
]

# ---- Chequeos Local ----
loc_checks = [
    ("views span (.views)", present(r'<span[^>]*class=["\\\']views["\\\']', loc)),
    ("AdSense", "pagead2.googlesyndication.com/pagead/js/adsbygoogle.js" in loc),
    ("footer: /terms", present(r'href=["\\\']/terms["\\\']', loc)),
    ("footer: /privacy", present(r'href=["\\\']/privacy["\\\']', loc)),
]

report.append("\n-- LIVE checks --")
for k,v in live_checks: report.append(("OK  - " if v else "FAIL- ") + k)

report.append("\n-- LOCAL checks --")
for k,v in loc_checks: report.append(("OK  - " if v else "FAIL- ") + k)

# ---- Headers /api/notes (paginación/CORS) ----
has_link = "Link:" in hdrs or "link:" in hdrs
has_acao = "Access-Control-Allow-Origin" in hdrs or "access-control-allow-origin" in hdrs
has_acam = "Access-Control-Allow-Methods" in hdrs or "access-control-allow-methods" in hdrs
has_acah = "Access-Control-Allow-Headers" in hdrs or "access-control-allow-headers" in hdrs
has_max  = "Access-Control-Max-Age" in hdrs or "access-control-max-age" in hdrs

report.append("\n-- /api/notes headers --")
report.append("OK  - Link rel=next" if has_link else "FAIL- Link rel=next")
report.append("OK  - ACAO" if has_acao else "FAIL- ACAO")
report.append("OK  - ACAM" if has_acam else "FAIL- ACAM")
report.append("OK  - ACAH" if has_acah else "FAIL- ACAH")
report.append("OK  - Max-Age" if has_max else "FAIL- Max-Age")

# ---- Sugerencias (ordenadas por impacto) ----
fixes=[]
if not live_checks[0][1]: fixes.append("Inyectar <span class=\"views\"> en las tarjetas de notas.")
if not live_checks[1][1]: fixes.append("Insertar script AdSense en <head> (client=ca-pub-XXXX).")
if live_checks[2][1]:    fixes.append("Remover subtítulo duplicado (<h2>).")
if live_checks[3][1]:    fixes.append("Eliminar referencias a Service Worker para evitar caché vieja.")
if not live_checks[6][1] or not live_checks[7][1]:
    fixes.append("Asegurar enlaces legales /terms y /privacy y páginas mínimas.")
if not has_link:
    fixes.append("Agregar cabecera HTTP Link: rel=\"next\" en GET /api/notes (paginación).")

report.append("\n-- Suggested fixes (high → low) --")
for fx in fixes: report.append(f"- {fx}")

# ---- Volcado breve de headers para trazabilidad ----
report.append("\n-- Raw headers /api/notes --")
report.append(hdrs.strip() or "(sin headers)")

io.open(rep_path, "w", encoding="utf-8").write("\n".join(report) + "\n")
print(f"OK: {rep_path}")
PY

echo "OK: $LIVE_HTML"
echo "OK: $LOCAL_HTML"
echo "OK: $REPORT"
echo "OK: $HDRS"
echo "OK: $HEALTH"
