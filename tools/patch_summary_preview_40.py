#!/usr/bin/env python3
import pathlib, re, sys, shutil

IDX = pathlib.Path("backend/static/index.html")
if not IDX.exists():
    print("✗ backend/static/index.html no existe"); sys.exit(2)

html = IDX.read_text(encoding="utf-8")
bak  = IDX.with_suffix(".html.bak")
changed = False

# 1) Dedup tagline fijo heredado (defensivo)
new = re.sub(r'<div\s+id="tagline"[^>]*>.*?</div>', '', html, flags=re.I|re.S)
if new != html:
    html, changed = new, True

# 2) Inyectar script de preview 40c + toggle "… Ver más" (idempotente por marcador)
marker = "<!-- SUMMARY-PREVIEW-40 START -->"
if marker not in html:
    block = f"""{marker}
<script>
(function(){
  if (window.__preview40_applied__) return;
  window.__preview40_applied__ = true;

  function applyPreview(root) {{
    const MAX = 40;
    const nodes = root.querySelectorAll('.note-text,[data-note-text],.note .text');
    nodes.forEach(el => {{
      if (el.dataset.previewApplied === "1") return;
      const full = (el.textContent || '').trim();
      if (full.length <= MAX) {{ el.dataset.previewApplied = "1"; return; }}
      const short = full.slice(0, MAX);
      const span = document.createElement('span');
      span.className = 'note-preview';
      span.textContent = short + '… ';

      const more = document.createElement('button');
      more.type = 'button';
      more.className = 'see-more';
      more.textContent = 'Ver más';
      more.style.border = 'none';
      more.style.background = 'transparent';
      more.style.cursor = 'pointer';
      more.style.textDecoration = 'underline';
      more.addEventListener('click', () => {{
        if (el.dataset.expanded === '1') {{
          el.dataset.expanded = '0';
          span.textContent = short + '… ';
          more.textContent = 'Ver más';
        }} else {{
          el.dataset.expanded = '1';
          span.textContent = full + ' ';
          more.textContent = 'Ver menos';
        }}
      }});
      el.textContent = '';
      el.appendChild(span);
      el.appendChild(more);
      el.dataset.previewApplied = "1";
    }});
  }}

  document.addEventListener('DOMContentLoaded', () => applyPreview(document));
  const obs = new MutationObserver(muts => {{
    muts.forEach(m => m.addedNodes && m.addedNodes.forEach(n => {{
      if (n.nodeType === 1) applyPreview(n);
    }}));
  }});
  obs.observe(document.documentElement, {{childList:true,subtree:true}});
})();
</script>
<!-- SUMMARY-PREVIEW-40 END -->
"""
    html = re.sub(r'</body>', block + '\n</body>', html, count=1, flags=re.I)
    changed = True

if not changed:
    print("OK: preview 40c ya presente"); sys.exit(0)

if not bak.exists():
    shutil.copyfile(IDX, bak)
IDX.write_text(html, encoding="utf-8")
print("patched: preview 40c + ver más (backup creado)")
