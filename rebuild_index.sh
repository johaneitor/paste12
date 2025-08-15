#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

HTML="frontend/index.html"
CSS="frontend/css/styles.css"
ts=$(date +%s)

# Backups
cp -p "$HTML" "$HTML.recover.$ts" 2>/dev/null || true
echo "🗂️  Backup: $HTML.recover.$ts"

# 1) Obtener logo en base64 (preferir el que ya esté embebido; si no, codificar PNG más reciente)
PY_B64=$(python - <<'PY'
import re, base64, glob, os, pathlib, sys
p = pathlib.Path("frontend/index.html")
b64 = ""
if p.exists():
    m = re.search(r'src="(data:image/png;base64,[^"]+)"', p.read_text())
    if m: 
        print(m.group(1)); sys.exit(0)

# No había data-URI: buscar PNG más reciente
cands = []
cands += glob.glob("/mnt/data/*.png")
cands += glob.glob("frontend/img/*.png")
cands.sort(key=lambda f: os.path.getmtime(f), reverse=True)
if cands:
    with open(cands[0], "rb") as f:
        b64 = "data:image/png;base64," + base64.b64encode(f.read()).decode()
print(b64)
PY
)

# 2) Escribir un index.html sano
cat > "$HTML" <<HTML
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Paste12 — notas que desaparecen</title>
<link rel="stylesheet" href="css/styles.css">
</head>
<body>
  <header class="hero" style="text-align:center;padding-top:24px">
    <div class="logo">
      ${PY_B64:+<img class="logo-img" alt="Logo" src="$PY_B64">}
    </div>
    <h1>Paste12</h1>
    <p class="playline">Haz un regalo • Dime un secreto • Reta a un amigo</p>
  </header>

  <main class="container" style="max-width:820px;margin:0 auto;padding:16px">
    <form id="form" class="card" style="padding:16px;border-radius:16px">
      <textarea id="text" placeholder="Escribe tu nota…" rows="5" style="width:100%"></textarea>
      <div style="display:flex;gap:12px;align-items:center;justify-content:space-between;margin-top:10px">
        <label>Duración:
          <select name="expire_hours" id="duration">
            <option value="12">12 horas</option>
            <option value="24">1 día</option>
            <option value="168" selected>7 días</option>
            <option value="336">14 días</option>
            <option value="672">28 días</option>
          </select>
        </label>
        <button type="submit" class="primary">Publicar</button>
      </div>
    </form>

    <ul id="notes" class="notes" style="list-style:none;padding:0;margin:18px 0 10px"></ul>
    <nav id="pagination" class="pagination" style="display:flex;gap:6px;justify-content:center;margin:10px 0 40px"></nav>
  </main>

  <footer class="legal">© 2025 Paste12 — Todos los derechos reservados · Este sitio es recreativo. No publiques datos sensibles.</footer>
  <script src="js/app.js"></script>
</body>
</html>
HTML
echo "✅ index.html reconstruido"

# 3) Asegurar estilos básicos para que se vea bien
if ! grep -q ".legal" "$CSS"; then
cat >> "$CSS" <<'CSS'

/* --- reconstrucción mínima --- */
.hero h1{font-size:2.4rem;margin:.2rem 0}
.playline{font-weight:600;color:#fff;opacity:.9;margin:-.3rem 0 1rem;text-align:center;
  text-shadow:0 0 8px #30eaff,0 0 4px #ff00ff}
footer.legal{margin:3rem auto 1rem;text-align:center;font-size:.9rem;opacity:.85}
.notes .note{background:rgba(0,0,0,.15);border-radius:16px;padding:12px;margin:10px 0}
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-top:.4rem}
.like-btn{background:#ff00ff;color:#fff;border:none;border-radius:.6rem;padding:.35rem .7rem;cursor:pointer}
CSS
fi

# 4) Reiniciar servidor
pkill -f waitress 2>/dev/null || true
source venv/bin/activate
python run.py &
echo "🚀  Reiniciado. Abre la URL impresa. Si no ves cambios, fuerza recarga (borrar caché)."
