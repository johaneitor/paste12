#!/usr/bin/env bash
set -euo pipefail

# Uso:
#   tools/frontend_purify_unify_v3.sh [ADSENSE_CLIENT] [BASE]
# Ej:
#   tools/frontend_purify_unify_v3.sh ca-pub-9479870293204581 "https://paste12-rmsk.onrender.com"
#
# Notas:
# - No toca nada fuera de ./frontend.
# - Deja auditoría y copias en /sdcard/Download si existe y es escribible.

ADSENSE_CLIENT="${1:-${ADSENSE_CLIENT:-ca-pub-9479870293204581}}"
BASE="${2:-}"

HTML="frontend/index.html"
OUT_DIR="/sdcard/Download"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
AUD="${OUT_DIR}/frontend-audit-${TS}.txt"

log() { printf '%s %s\n' "[$(date -u +%H:%M:%S)]" "$*" ; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: falta comando $1"; exit 1; }; }
ensure_dir() { [[ -d "$1" ]] || { mkdir -p "$1" 2>/dev/null || true; }; }

need sed
need awk
need grep
need python

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

# --- Backups y preparación ---
ensure_dir "$OUT_DIR"
BAK="frontend/index.${TS}.bak"
cp -f "$HTML" "$BAK"
log "Backup: $BAK"

# --- 1) Purga de variantes index-*.html (no la actual) ---
find frontend/ -maxdepth 1 -type f -name 'index-*.html' ! -name "$(basename "$BAK")" -print -delete | sed 's/^/purga: /' || true

# --- 2) Asegurar AdSense + meta description + footer legal ---
python - <<PY
import io, re, sys, os
p = "$HTML"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

def has_adsense(html: str) -> bool:
    return re.search(r'adsbygoogle\.js\?client=$', 'x') is not None  # dummy to keep pyc happy

ads_re = re.compile(r'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js\?client=', re.I)
if not ads_re.search(s):
    s = re.sub(r'</head>', 
               f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${ADSENSE_CLIENT}" crossorigin="anonymous"></script>\n</head>',
               s, flags=re.I)

if not re.search(r'<meta\s+name=["\']description["\']', s, re.I):
    s = re.sub(r'(<head[^>]*>)', r'\1\n<meta name="description" content="Paste12: comparte notas anónimas e historias inspiradoras de forma simple."/>', s, flags=re.I)

# Footer con /terms y /privacy
need_terms = not re.search(r'href=["\']/terms["\']', s, re.I)
need_priv  = not re.search(r'href=["\']/privacy["\']', s, re.I)
if need_terms or need_priv:
    if re.search(r'</footer>', s, re.I):
        if need_terms:
            s = re.sub(r'(</footer>)', '<a href="/terms">Términos y Condiciones</a>\n\\1', s, flags=re.I)
        if need_priv:
            s = re.sub(r'(</footer>)', '<a href="/privacy">Política de Privacidad</a>\n\\1', s, flags=re.I)
    else:
        footer = '<footer style="margin-top:2rem;opacity:.85"><a href="/terms">Términos y Condiciones</a> · <a href="/privacy">Política de Privacidad</a></footer>'
        s = re.sub(r'</body>', footer + '\n</body>', s, flags=re.I)

# --- 3) Métricas visibles: likes/views/reports por si la plantilla no las envuelve ---
# Añadimos un micro-enhancer idempotente que normaliza spans tras el render.
if 'p12-metrics-enhancer-v1' not in s:
    enhancer = """
<script id="p12-metrics-enhancer-v1">
(function(){
  try{
    const attach = () => {
      const metaBlocks = Array.from(document.querySelectorAll('.meta, .note .meta, .card .meta'));
      for (const mb of metaBlocks){
        let t = mb.innerHTML;
        // likes
        t = t.replace(/(❤\\s*)([0-9]+|\\$\\{[^}]+\\})(?![^<]*<\\/span>)/, '<span class="likes">$1$2</span>');
        // views
        t = t.replace(/(👁\\s*)([0-9]+|\\$\\{[^}]+\\})(?![^<]*<\\/span>)/, '<span class="views">$1$2</span>');
        // reports (si no hay)
        if(!/class=["\\']reports["\\']/.test(t)){
          t = t.replace(/(<span class="views"[^>]*>[^<]*<\\/span>)/, '$1 · <span class="reports">🚩 0</span>');
        }
        mb.innerHTML = t;
      }
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', attach);
    else attach();
  }catch(e){ console.warn('metrics-enhancer', e); }
})();
</script>
"""
    s = s.replace("</body>", enhancer + "\n</body>")

# Compactar saltos de línea excesivos
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("mod: index.html actualizado")
else:
    print("mod: index.html sin cambios")
PY

# Crear páginas legales mínimas si no existen
if [[ ! -f frontend/terms.html ]]; then
  cat > frontend/terms.html <<'HT'
<!doctype html><meta charset="utf-8"><title>Paste12 - Términos</title>
<style>body{font:16px/1.6 system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:64rem}</style>
<h1>Términos y condiciones</h1><p>Documento mínimo de términos.</p>
HT
  log "Creado: frontend/terms.html"
fi
if [[ ! -f frontend/privacy.html ]]; then
  cat > frontend/privacy.html <<'HP'
<!doctype html><meta charset="utf-8"><title>Paste12 - Privacidad</title>
<style>body{font:16px/1.6 system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:64rem}</style>
<h1>Política de privacidad</h1><p>Documento mínimo de privacidad.</p>
HP
  log "Creado: frontend/privacy.html"
fi

# --- 4) Quitar service workers y restos legacy (idempotente) ---
sed -i.bak '/serviceWorker\.register/d;/navigator\.serviceWorker/d;/caches\./d;/LEGACY-KEEP:/d;/TODO-OLD:/d' "$HTML" || true

# --- 5) Auditoría local y (si BASE) remota ---
{
  echo "== Frontend audit =="
  echo "ts: ${TS}"
  echo "- index existe: OK"
  if grep -qi 'adsbygoogle\.js?client=' "$HTML"; then echo "OK  - AdSense en <head>"; else echo "FAIL- AdSense ausente"; fi
  if grep -q 'p12-metrics-enhancer-v1' "$HTML"; then echo "OK  - metrics enhancer"; else echo "WARN- metrics enhancer ausente"; fi
  if grep -qi '<footer' "$HTML" && grep -qi 'href="/terms"' "$HTML" && grep -qi 'href="/privacy"' "$HTML"; then echo "OK  - footer legal"; else echo "FAIL- footer legal"; fi
  if grep -qi '<meta name="description"' "$HTML"; then echo "OK  - meta description"; else echo "FAIL- meta description"; fi
} >"$AUD"

# Copia del HTML local a Downloads
cp -f "$HTML" "${OUT_DIR}/index-local-${TS}.html" 2>/dev/null || true

# Verificación remota opcional (cache bust)
if [[ -n "${BASE}" ]]; then
  need curl
  URL="${BASE%/}/?debug=1&nosw=1&v=${TS}"
  LIVE="${OUT_DIR}/index-live-${TS}.html"
  if curl -fsSL "$URL" -o "$LIVE"; then
    echo "OK  - GET live" >>"$AUD"
    if grep -qi 'adsbygoogle\.js?client=' "$LIVE"; then echo "OK  - live AdSense" >>"$AUD"; else echo "WARN- live sin AdSense" >>"$AUD"; fi
    if grep -q 'class="views"' "$LIVE"; then echo "OK  - live .views" >>"$AUD"; else echo "WARN- live sin .views" >>"$AUD"; fi
  else
    echo "WARN- no pude obtener ${URL}" >>"$AUD"
  fi
fi

log "Auditoría: $AUD"
echo "OK: Frontend purificado/unificado."
