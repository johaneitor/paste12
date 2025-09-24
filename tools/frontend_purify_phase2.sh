#!/usr/bin/env bash
set -euo pipefail

HTML="frontend/index.html"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
BAK="frontend/index.$TS.phase2.bak"
cp -f "$HTML" "$BAK"
echo "Backup: $BAK"

# 1) Páginas mínimas de términos/privacidad
mkdir -p frontend
for pg in terms privacy; do
  f="frontend/${pg}.html"
  if [[ ! -f "$f" ]]; then
    cat > "$f" <<PG
<!doctype html>
<meta charset="utf-8">
<title>Paste12 - ${pg^}</title>
<style>body{font:16px/1.5 system-ui,Segoe UI,Roboto,Arial;margin:2rem;max-width:56rem}</style>
<h1>${pg^}</h1>
<p>Documento ${pg} de Paste12. (Versión mínima).</p>
PG
    echo "Creado: $f"
  fi
done

# 2) Footer legal en index + normalización de enlaces
python - <<'PY'
import io, re

p = "frontend/index.html"
s = io.open(p, "r", encoding="utf-8").read()
orig = s

# Normalizar destinos típicos viejos a rutas limpias
s = re.sub(r'href=["\'](?:\.?/)?terms(?:\.html)?["\']', 'href="/terms"', s, flags=re.I)
s = re.sub(r'href=["\'](?:\.?/)?privacy(?:\.html)?["\']', 'href="/privacy"', s, flags=re.I)

has_terms = re.search(r'href=["\']/terms["\']', s, re.I) is not None
has_priv  = re.search(r'href=["\']/privacy["\']', s, re.I) is not None

if not (has_terms and has_priv):
    # Insertar footer si no existe
    if re.search(r'</footer>', s, re.I) is None:
        footer = (
            '\n<footer style="margin-top:2rem;opacity:.85">'
            '<a href="/terms">Términos y Condiciones</a> · '
            '<a href="/privacy">Política de Privacidad</a>'
            '</footer>\n'
        )
        s = re.sub(r'</body>', footer + '</body>', s, flags=re.I, count=1)
    else:
        # Añadir enlaces dentro del footer existente si faltan
        def ensure_link(txt, href):
            nonlocal s
            if re.search(re.escape(href), s, re.I):
                return
            s = re.sub(r'(</footer>)', f'  <a href="{href}">{txt}</a>\n\\1', s, flags=re.I)

        if not has_terms:
            ensure_link("Términos y Condiciones", "/terms")
        if not has_priv:
            ensure_link("Política de Privacidad", "/privacy")

# Limpieza de saltos excesivos
s = re.sub(r'\n{3,}', '\n\n', s)

if s != orig:
    io.open(p, "w", encoding="utf-8").write(s)
    print("OK: footer/enlaces legales verificados/insertados.")
else:
    print("INFO: enlaces legales ya estaban OK.")
PY

# 3) Quitar referencias a service worker/caché vieja
sed -i.bak '/serviceWorker\.register/d' "$HTML" || true
sed -i.bak '/navigator\.serviceWorker/d' "$HTML" || true
# 4) Limpieza menor de comentarios marcados como legado
sed -i.bak '/LEGACY-KEEP:/d' "$HTML" || true
sed -i.bak '/TODO-OLD:/d' "$HTML" || true

echo "OK: Fase 2 aplicada."
