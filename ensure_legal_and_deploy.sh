#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"

ts=$(date +%s)
# 1) Asegura legal.html
mkdir -p frontend
cat > frontend/legal.html <<'HTML'
<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Términos y Privacidad · Paste12</title>
<link rel="stylesheet" href="/css/styles.css">
<style>main{max-width:900px;margin:30px auto;padding:20px;background:rgba(0,0,0,.25);border-radius:16px;color:#fff}</style>
</head><body>
<main>
  <h1>Paste12 · Términos y Privacidad</h1>
  <p>Este sitio es recreativo. No publiques datos sensibles ni ilegales.</p>
  <h2>Contenido y moderación</h2>
  <ul>
    <li>Las notas expiran automáticamente.</li>
    <li>Los usuarios pueden reportar; 5 reportes eliminan la nota.</li>
    <li>Se bloquea spam y contenido no permitido.</li>
  </ul>
  <h2>Datos</h2>
  <p>No se exige registro. Se usan cookies locales para likes/reportes y logs mínimos para seguridad.</p>
  <h2>Contacto</h2>
  <p>Si ves un abuso, usa “Reportar” o escribe a admin@tu-dominio.</p>
</main>
</body></html>
HTML
echo "✓ frontend/legal.html"

# 2) Endpoint /__version para comprobar qué commit está en producción
python - <<'PY'
from pathlib import Path, re
p = Path("backend/__init__.py")
code = p.read_text(encoding="utf-8")
if "/__version" not in code:
    code = re.sub(r'(app\s*=\s*Flask[^\n]*\)\s*\n)',
                  r'\1\n    @app.get("/__version")\n'
                  r'    def __version():\n'
                  r'        try:\n'
                  r'            return {"version": open("VERSION").read().strip()}\n'
                  r'        except Exception:\n'
                  r'            return {"version":"unknown"}\n',
                  code, count=1)
    p.write_text(code, encoding="utf-8")
    print("✓ backend/__version añadido")
else:
    print("• backend/__version ya existía")
PY

# 3) Guarda el hash actual en VERSION y push
git rev-parse HEAD > VERSION
git add -A
git commit -m "fix: asegurar legal.html y endpoint /__version" || true
git push
echo "🚀 Push hecho. Render debería redeployar."
echo "👉 Cuando termine el deploy, prueba:"
echo "   https://TU-DOMINIO/__version   (debe devolver el hash)"
echo "   https://TU-DOMINIO/legal.html  (ya no 404)"
echo "   https://TU-DOMINIO/ads.txt     (si usas AdSense)"
