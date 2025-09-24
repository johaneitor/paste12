#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import re
from pathlib import Path
p=Path("backend/frontend/js/app.js")
s=p.read_text(encoding="utf-8")
orig=s
# Inserta justo después de crear el <li>
s=re.sub(
    r"(const\s+li\s*=\s*document\.createElement\(['\"]li['\"]\);\s*)(\r?\n)",
    r"\1\n  // IDs para actions.js (kebab menu)\n"
    r"  try { li.dataset.noteId = String((note && note.id) || (n && n.id) || (item && item.id) || (row && row.id));\n"
    r"        if (li.dataset.noteId) li.id = 'note-' + li.dataset.noteId; } catch (e) {}\n"
    r"  li.classList && li.classList.add('note');\n\2",
    s, count=1
)
if s==orig:
    s=re.sub(
        r"(document\.createElement\(['\"]li['\"]\);\s*)(\r?\n)",
        r"\1\n  // IDs para actions.js (kebab menu)\n"
        r"  try { li.dataset.noteId = String((note && note.id) || (n && n.id) || (item && item.id) || (row && row.id));\n"
        r"        if (li.dataset.noteId) li.id = 'note-' + li.dataset.noteId; } catch (e) {}\n"
        r"  li.classList && li.classList.add('note');\n\2",
        s, count=1
    )
if s!=orig:
    p.write_text(s, encoding="utf-8")
    print("patched app.js: set data-note-id + .note")
else:
    print("No encontré dónde creás <li>. Si renderizás distinto, añadí manualmente donde armes cada tarjeta:")
    print("  li.dataset.noteId = String(note.id); li.id = 'note-'+note.id; li.classList.add('note');")
PY
git add backend/frontend/js/app.js || true
git commit -m "feat(frontend): etiquetar cada nota con data-note-id y .note para mostrar menú ⋮" || true
git push origin main
