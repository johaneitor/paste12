#!/usr/bin/env bash
set -euo pipefail

CLIENT="${1:-}"
if [[ -z "$CLIENT" ]]; then
  echo "Uso: $0 CA-PUB-ID    (ej: $0 ca-pub-9479870293204581)"; exit 2
fi

TARGET="contract_shim.py"
[[ -f "$TARGET" ]] || { echo "ERROR: falta $TARGET"; exit 3; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="${TARGET}.${TS}.bak"
cp -f "$TARGET" "$BAK"
echo "[hotfix-legal] Backup: $BAK"

# Si ya fue aplicado, solo actualiza el CLIENT en el bloque.
if grep -q "p12-legal-mw-v1" "$TARGET"; then
  python - <<PY
import io,re,sys
p="$TARGET"
s=io.open(p,"r",encoding="utf-8").read()
s=re.sub(r'(P12_ADSENSE_CLIENT\s*=\s*")[^"]+(")',
         r'\1${CLIENT}\2', s, flags=re.M)
io.open(p,"w",encoding="utf-8").write(s)
print("Actualizado: P12_ADSENSE_CLIENT=${CLIENT}")
PY
else
  # Inyectar bloque WSGI middleware al final de contract_shim.py
  cat >> "$TARGET" <<'PY'
# [p12-legal-mw-v1] —— Legal pages WSGI middleware (terms/privacy) + AdSense head
import os, re
from pathlib import Path

# Cliente AdSense (se sobreescribe desde script)
P12_ADSENSE_CLIENT = "REPLACE_ME"

_P12_AD_TAG = ('<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'
               '?client={{CID}}" crossorigin="anonymous"></script>').replace("{{CID}}", P12_ADSENSE_CLIENT)

def _p12_has_head(html): 
    return bool(re.search(r'<head[^>]*>', html, re.I))

def _p12_ensure_head_with_adsense(html):
    s = html
    if not _p12_has_head(s):
        # envolver en documento mínimo
        body = s if '<body' in s.lower() else ('<body>' + s + '</body>')
        s = ('<!doctype html>\n<html lang="es"><head><meta charset="utf-8"/>'
             + _P12_AD_TAG + '</head>' + body + '</html>')
    else:
        # asegurar el script AdSense antes de </head>
        if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' not in s:
            s = re.sub(r'</head>', _P12_AD_TAG + '\n</head>', s, flags=re.I)
    return s

def _p12_load_file_or_default(name, title):
    fp = Path("frontend")/name
    if fp.exists():
        try:
            s = fp.read_text("utf-8", errors="replace")
        except Exception:
            s = f"<!doctype html><meta charset=utf-8><title>{title}</title><h1>{title}</h1><p>(contenido mínimo)</p>"
    else:
        s = f"<!doctype html><meta charset=utf-8><title>{title}</title><h1>{title}</h1><p>(contenido mínimo)</p>"
    # stats mínimos (por coherencia visual)
    if 'id="p12-stats"' not in s:
        s += '\n<div id="p12-stats" class="stats"><span class="views" data-views="0">👁️ <b>0</b></span><span class="likes" data-likes="0">❤️ <b>0</b></span><span class="reports" data-reports="0">🚩 <b>0</b></span></div>\n'
    return _p12_ensure_head_with_adsense(s)

def _p12_resp(start_response, body, status="200 OK", ctype="text/html; charset=utf-8"):
    if isinstance(body, str): body = body.encode("utf-8")
    start_response(status, [("Content-Type", ctype), ("Cache-Control","no-cache")])
    return [body]

def _p12_legal_mw(app):
    TERMS = _p12_load_file_or_default("terms.html", "Términos y Condiciones")
    PRIV  = _p12_load_file_or_default("privacy.html", "Política de Privacidad")
    def _mw(environ, start_response):
        try:
            path = environ.get("PATH_INFO","") or ""
            if path.rstrip("/") == "/terms":
                return _p12_resp(start_response, TERMS)
            if path.rstrip("/") == "/privacy":
                return _p12_resp(start_response, PRIV)
        except Exception:
            # en caso de error, seguir al app principal
            pass
        return app(environ, start_response)
    return _mw

# envolver 'application' si existe
try:
    application  # noqa
    application = _p12_legal_mw(application)
except NameError:
    pass
PY

  # insertar el client real
  python - <<PY
import io,re
p="$TARGET"
s=io.open(p,"r",encoding="utf-8").read()
s=re.sub(r'(P12_ADSENSE_CLIENT\s*=\s*")[^"]+(")', r'\1${CLIENT}\2', s, flags=re.M)
io.open(p,"w",encoding="utf-8").write(s)
print("Insertado bloque legal middleware + AdSense client: ${CLIENT}")
PY
fi

# Gate de compilación
python -m py_compile "$TARGET" && echo "py_compile OK"

echo "Listo. Despliega con gunicorn como venías usando."
echo "Sugerido: Clear build cache + Deploy en Render."
