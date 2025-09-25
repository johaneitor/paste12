#!/usr/bin/env bash
set -euo pipefail
CID="${1:-}"
[[ -n "$CID" ]] || { echo "USO: $0 ca-pub-XXXXXXXXXXXXXXX"; exit 2; }
HTML="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
[[ -f "$HTML" ]] || { echo "ERROR: falta $HTML"; exit 1; }
cp -f "$HTML" "$HTML.$TS.reconcile.bak"
echo "[reconcile] Backup: $HTML.$TS.reconcile.bak"

ADS_CLIENT="$CID" HTML_PATH="$HTML" python3 - <<'PY'
import io, re, os
p=os.environ["HTML_PATH"]; cid=os.environ["ADS_CLIENT"]
s=io.open(p,"r",encoding="utf-8").read(); orig=s

def ensure_meta(s):
    if re.search(r'google-adsense-account', s, re.I) and cid in s:
        return s
    s=re.sub(r'\s*<meta\s+name=["\']google-adsense-account["\'][^>]*>\s*','',s,flags=re.I)
    s=re.sub(r'(<head[^>]*>)', r'\1\n<meta name="google-adsense-account" content="%s">'%cid, s, count=1, flags=re.I)
    return s

def ensure_script(s):
    if re.search(r'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js', s) and cid in s:
        return s
    tag=f'<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={cid}" crossorigin="anonymous"></script>'
    s=re.sub(r'</head>', tag+'\n</head>', s, count=1, flags=re.I) if re.search(r'</head>', s, re.I) else s+('\n'+tag+'\n')
    return s

def ensure_views_span(s):
    if re.search(r'<span[^>]+class=["\']views["\']', s, re.I):
        return s
    # inyectar tras primer <h1>
    return re.sub(r'(</h1>)', r'\1\n<p class="meta">👁️ <span class="views">0</span> vistas</p>', s, count=1, flags=re.I)

def dedup_titles_and_h1(s):
    # <title> duplicados -> dejar el primero
    titles=re.findall(r'<title[^>]*>.*?</title>', s, flags=re.I|re.S)
    if len(titles)>1:
        s=re.sub(r'<title[^>]*>.*?</title>', titles[0], s, flags=re.I|re.S)
    # h1 duplicados por texto -> mantener primera aparición
    seen=set()
    def repl(m):
        txt=re.sub(r'\s+',' ',m.group(1)).strip()
        if txt.lower() in seen: return ''
        seen.add(txt.lower()); return m.group(0)
    s=re.sub(r'<h1[^>]*>(.*?)</h1>', repl, s, flags=re.I|re.S)
    return re.sub(r'\n{3,}', '\n\n', s)

for fn in (ensure_meta, ensure_script, ensure_views_span, dedup_titles_and_h1):
    s=fn(s)

if s!=orig:
    io.open(p,"w",encoding="utf-8").write(s)
    print("OK: index reconciliado")
else:
    print("INFO: index ya estaba OK")
PY
