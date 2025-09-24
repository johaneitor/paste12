#!/usr/bin/env bash
set -Eeuo pipefail

INDEX="frontend/index.html"
JS="frontend/js/app.js"
LOG="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/paste12_server.log"
mkdir -p "$(dirname "$LOG")"

echo "➤ Backups"
cp -f "$INDEX" "$INDEX.bak.$(date +%s)" 2>/dev/null || true
cp -f "$JS"    "$JS.bak.$(date +%s)"    2>/dev/null || true

python - <<'PY'
from pathlib import Path
import re

# --- Patch index.html: botón debajo del contenido principal ---
p = Path("frontend/index.html")
html = p.read_text(encoding="utf-8")

if 'id="loadMore"' not in html:
    # intenta insertarlo antes de </main>; si no, antes de </body>
    btn = '\n  <button id="loadMore" class="load-more" style="display:none;margin:12px auto;padding:8px 14px;border:1px solid #253044;border-radius:10px;background:#0d1320;color:#eaf2ff">Cargar más</button>\n'
    if re.search(r"</main>", html, re.I):
        html = re.sub(r"</main>", btn + r"\n</main>", html, flags=re.I)
    else:
        html = re.sub(r"</body>", btn + r"\n</body>", html, flags=re.I)
    print("index.html: botón 'Cargar más' insertado.")
else:
    print("index.html: ya tenía el botón 'Cargar más'.")

Path("frontend/index.html").write_text(html, encoding="utf-8")

# --- Patch app.js: agregar paginación por cursor ---
js_p = Path("frontend/js/app.js")
js = js_p.read_text(encoding="utf-8")

# 1) Desactivar la llamada directa a fetchNotes() para evitar doble carga
js_new = re.sub(r"^\s*fetchNotes\(\);\s*$", "/* fetchNotes() -> reemplazado por paginación */", js, flags=re.M)
replaced = js_new != js
js = js_new

# 2) Agregar bloque de paginación si no existe ya
if "X-Next-After" not in js:
    block = r"""
/* === Paginación por cursor (after_id + limit) === */
(() => {
  const $list = document.getElementById('notes');
  const $btn  = document.getElementById('loadMore');
  if (!$list || !$btn) return;

  let after = null;
  const LIMIT = 10;

  async function fetchPage(opts = { append: false }) {
    try {
      const qs = new URLSearchParams({ limit: String(LIMIT) });
      if (after) qs.set('after_id', after);

      const res = await fetch('/api/notes?' + qs.toString());
      const data = await res.json();

      if (!opts.append) $list.innerHTML = '';
      data.forEach(n => $list.appendChild(renderNote(n)));

      const next = res.headers.get('X-Next-After');
      after = next && next.trim() ? next.trim() : null;
      $btn.hidden = !after;
      $btn.style.display = after ? 'block' : 'none';
    } catch (e) {
      console.error('pagination fetchPage failed:', e);
    }
  }

  // Primera carga
  fetchPage({ append: false });

  // Botón cargar más
  $btn.addEventListener('click', () => fetchPage({ append: true }));

  // Al publicar una nota, recargar primera página (si existe el form)
  try {
    const $form = document.getElementById('noteForm');
    if ($form) {
      $form.addEventListener('submit', () => {
        after = null;
        setTimeout(() => fetchPage({ append: false }), 200);
      });
    }
  } catch (_) {}
})();
"""
    js += "\n" + block + "\n"
    print("app.js: bloque de paginación añadido.")
else:
    print("app.js: ya tenía lógica de paginación.")

if replaced:
    print("app.js: llamada a fetchNotes() desactivada.")
js_p.write_text(js, encoding="utf-8")
PY

echo "➤ Restart local"
pkill -f "python .*run\\.py" 2>/dev/null || true
pkill -f "waitress" 2>/dev/null || true
pkill -f "flask" 2>/dev/null || true
sleep 1
nohup python run.py >"$LOG" 2>&1 & disown || true
sleep 2

echo "➤ Smoke header X-Next-After (limit=2)"
curl -sSI 'http://127.0.0.1:8000/api/notes?limit=2' | tr -d '\r' | grep -i '^x-next-after:' || echo "(sin X-Next-After) quizá no hay más páginas"

echo "➤ (Opcional) Commit"
git add frontend/index.html frontend/js/app.js tools/add_load_more_button_and_js.sh || true
git commit -m "feat(ui): botón 'Cargar más' y paginación por cursor (after_id + limit) en frontend" || true
