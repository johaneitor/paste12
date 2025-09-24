#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
from pathlib import Path, re
p = Path("backend/frontend/js/actions.js")
s = p.read_text(encoding="utf-8")
orig = s
if "function tagDomByOrder" not in s:
    s = s.replace(
        "window.addEventListener('DOMContentLoaded', () => {",
        """async function tagDomByOrder() {
  if (document.querySelector('[data-note-id]')) return;
  try {
    const r = await fetch('/api/notes?limit=50');
    if (!r.ok) return;
    const list = await r.json();
    if (!Array.isArray(list) || !list.length) return;
    const candidates = Array.from(new Set([
      ...document.querySelectorAll('[data-note-id], .note-card, .note, main li, .notes li, .note-list li, ul li')
    ])).filter(el => el && el.nodeType === 1);
    let i = 0;
    for (const el of candidates) {
      if (el.dataset && !el.dataset.noteId && list[i] && list[i].id != null) {
        el.dataset.noteId = String(list[i].id);
        if (!el.id) el.id = 'note-' + String(list[i].id);
        el.classList && el.classList.add('note');
        i++;
      }
      if (i >= list.length) break;
    }
  } catch {}
}
window.addEventListener('DOMContentLoaded', async () => {
  try { await tagDomByOrder(); } catch (e) {}
""", 1)
    p.write_text(s, encoding="utf-8")
    print("patched actions.js: fallback tagDomByOrder() añadido")
else:
    print("actions.js ya tenía tagDomByOrder() o no fue posible insertar")
PY
git add backend/frontend/js/actions.js || true
git commit -m "feat(frontend): fallback para etiquetar notas por orden y habilitar menú ⋮" || true
git push origin main
