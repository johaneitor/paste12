#!/usr/bin/env bash
set -Eeuo pipefail

# 1) Elegir carpeta de estáticos: usa la primera que exista (frontend/public/static/dist/build),
#    y si ninguna existe, crea public/
choose_static_dir() {
  for d in frontend public static dist build; do
    if [ -d "$d" ]; then echo "$d"; return; fi
  done
  echo "public"
}
STATIC_DIR="$(choose_static_dir)"
mkdir -p "$STATIC_DIR/js" "$STATIC_DIR/css"

echo "➤ Usando carpeta de estáticos: $STATIC_DIR"

# 2) Backups suaves si existen
for f in index.html js/app.js css/styles.css; do
  [ -f "$STATIC_DIR/$f" ] && cp -f "$STATIC_DIR/$f" "$STATIC_DIR/$f.bak.$(date +%s)" || true
done

# 3) Escribir index.html mínimo (SPA) + JS + CSS
cat > "$STATIC_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>paste12</title>
  <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
  <header class="topbar">
    <h1>paste12</h1>
    <span class="status" id="status">cargando…</span>
  </header>

  <main class="container">
    <section class="new-note">
      <h2>Crear nota</h2>
      <form id="noteForm">
        <input type="text" id="text" name="text" placeholder="Escribe tu nota…" required />
        <input type="number" id="hours" name="hours" min="1" max="720" value="24" />
        <button type="submit">Publicar</button>
      </form>
      <p class="hint">Acepta JSON, form-data o urlencoded. Aquí usamos form-data (navegador).</p>
    </section>

    <section>
      <h2>Notas</h2>
      <ul id="notes" class="notes"></ul>
    </section>
  </main>

  <script src="/js/app.js?v=1"></script>
</body>
</html>
HTML

cat > "$STATIC_DIR/js/app.js" <<'JS'
(function () {
  const $status = document.getElementById('status');
  const $list = document.getElementById('notes');
  const $form = document.getElementById('noteForm');

  function fmtISO(s) {
    try { return new Date(s).toLocaleString(); } catch { return s; }
  }

  async function fetchNotes() {
    $status.textContent = 'cargando…';
    try {
      const res = await fetch('/api/notes?page=1');
      const data = await res.json();
      $list.innerHTML = '';
      data.forEach(n => {
        const li = document.createElement('li');
        li.className = 'note';
        li.innerHTML = `
          <div class="txt">${n.text ?? ''}</div>
          <div class="meta">
            <span>id #${n.id}</span>
            <span> · </span>
            <span>${fmtISO(n.timestamp)}</span>
            <span> · expira: ${fmtISO(n.expires_at)}</span>
          </div>
        `;
        $list.appendChild(li);
      });
      $status.textContent = 'ok';
    } catch (e) {
      console.error(e);
      $status.textContent = 'error cargando';
    }
  }

  $form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const fd = new FormData($form);
    try {
      const res = await fetch('/api/notes', { method: 'POST', body: fd });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      // refrescar
      await fetchNotes();
      $form.reset();
      document.getElementById('hours').value = 24;
    } catch (e) {
      alert('No se pudo publicar la nota: ' + e.message);
    }
  });

  fetchNotes();
})();
JS

cat > "$STATIC_DIR/css/styles.css" <<'CSS'
:root { --bg:#0c0f14; --card:#141922; --muted:#8ea0b5; --fg:#eaf2ff; --accent:#5da5ff; }
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial, "Apple Color Emoji","Segoe UI Emoji"}
.topbar{display:flex;align-items:center;gap:12px;padding:12px 16px;border-bottom:1px solid #1f2632;background:#0e1218;position:sticky;top:0}
.topbar h1{margin:0;font-size:18px}
.status{color:var(--muted);font-size:12px}
.container{max-width:800px;margin:24px auto;padding:0 16px}
.new-note{background:var(--card);padding:12px;border-radius:12px;border:1px solid #1e2633;margin-bottom:20px}
.new-note h2{margin:0 0 8px 0;font-size:16px}
#noteForm{display:flex;gap:8px;flex-wrap:wrap}
#noteForm input[type="text"]{flex:1;min-width:240px;padding:10px;border-radius:10px;border:1px solid #243144;background:#121722;color:var(--fg)}
#noteForm input[type="number"]{width:96px;padding:10px;border-radius:10px;border:1px solid #243144;background:#121722;color:var(--fg)}
#noteForm button{padding:10px 14px;border-radius:10px;background:var(--accent);color:#001129;border:none;cursor:pointer}
.hint{color:var(--muted);font-size:12px;margin-top:6px}
.notes{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:10px}
.note{background:var(--card);padding:12px;border-radius:12px;border:1px solid #1e2633}
.note .txt{white-space:pre-wrap}
.note .meta{color:var(--muted);font-size:12px;margin-top:6px}
CSS

# 4) Reiniciar local y smokes
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LOG="$PREFIX/tmp/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

pkill -f "python .*run\.py" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "health=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/api/health)"
echo "/=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/)"
echo "/js/app.js=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/js/app.js)"
echo "/css/styles.css=$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/css/styles.css)"

# 5) Commit & push
git add "$STATIC_DIR/index.html" "$STATIC_DIR/js/app.js" "$STATIC_DIR/css/styles.css"
git commit -m "feat(ui): frontend mínimo (SPA) que lista y crea notas contra /api"
git push origin main || true

echo "➤ Hecho. Si usás Render, hacé redeploy (Clear build cache & deploy) y abrí la home."
