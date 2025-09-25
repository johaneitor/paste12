#!/usr/bin/env bash
set -euo pipefail
HTML="${1:-frontend/index.html}"
ADS="${2:-}"  # ej: ca-pub-xxxxxxxxxxxxxxxx

[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 2; }

TS="$(date -u +%Y%m%d-%H%M%SZ)"
cp -f "$HTML" "${HTML}.${TS}.reconcile.bak"
echo "[reconcile] Backup: ${HTML}.${TS}.reconcile.bak"

python - "$HTML" "$ADS" <<'PY'
import io, sys, re

path = sys.argv[1]
ads  = sys.argv[2] if len(sys.argv) > 2 else ""
s = io.open(path, 'r', encoding='utf-8').read()
orig = s

def ensure_ads_meta(s):
    if 'google-adsense-account' in s.lower():
        return s
    if not ads:
        return s
    tag = f'<meta name="google-adsense-account" content="{ads}">'
    m = re.search(r'<head[^>]*>', s, re.I)
    if m:
        i = m.end()
        return s[:i] + "\n  " + tag + "\n" + s[i:]
    return tag + "\n" + s

def ensure_ads_script(s):
    if 'pagead2.googlesyndication.com/pagead/js/adsbygoogle.js' in s:
        return s
    if not ads:
        return s
    tag = f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={ads}" crossorigin="anonymous"></script>'
    m = re.search(r'</head>', s, re.I)
    if m:
        i = m.start()
        return s[:i] + "  " + tag + "\n" + s[i:]
    return s + "\n" + tag + "\n"

def ensure_views_block(s):
    if re.search(r'class=["\']views["\']', s, re.I):
        return s
    block = '''
<section id="p12-stats" class="stats" style="margin-top:1rem;opacity:.88">
  <span class="views">0</span> views ·
  <span class="likes">0</span> likes ·
  <span class="reports">0</span> reports
</section>
'''.lstrip()
    m = re.search(r'</main>', s, re.I)
    if m:
        i = m.start()
        return s[:i] + block + s[i:]
    m = re.search(r'</body>', s, re.I)
    if m:
        i = m.start()
        return s[:i] + block + s[i:]
    return s + "\n" + block

s = ensure_ads_meta(s)
s = ensure_ads_script(s)
s = ensure_views_block(s)

if s != orig:
    io.open(path, 'w', encoding='utf-8').write(s)
    print("mod: index.html actualizado")
else:
    print("index.html ya cumplía (sin cambios)")
PY

echo "[reconcile] listo"
