#!/usr/bin/env bash
set -euo pipefail
# Inyecta <script id="single-note-shim"> si no existe
inject() {
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -q 'single-note-shim' "$f"; then
    echo "OK: $f ya tenía el shim"
    return 0
  fi
  cp -n "$f" "${f}.single_shim.bak" || true
  printf '\n<!-- single-note shim (safe, idempotente) -->\n<script id="single-note-shim">\n</script>\n' >> "$f"
  # pega el JS dentro del tag recién creado
  awk '1' "$f" > "$f.tmp"
  nodejs -e "const fs=require('fs');const p='$f.tmp';let s=fs.readFileSync(p,'utf8');let js=fs.readFileSync('tools/patch_frontend_single_shim.js','utf8');s=s.replace(/<script id=\"single-note-shim\">\\n<\\/script>/, '<script id=\"single-note-shim\">\\n'+js+'\\n</script>');fs.writeFileSync(p,s)" 2>/dev/null || \
  python - "$f.tmp" tools/patch_frontend_single_shim.js <<'PY'
import sys,re
f,js = sys.argv[1], open(sys.argv[2],'r',encoding='utf-8').read()
s=open(f,'r',encoding='utf-8').read()
s=re.sub(r'<script id="single-note-shim">\\s*</script>', '<script id="single-note-shim">\\n'+re.escape(js).replace('\\/','/')+'\\n</script>', s, count=1)
open(f,'w',encoding='utf-8').write(s)
PY
  mv "$f.tmp" "$f"
  echo "patched: $f (+single-note shim)"
}

inject backend/static/index.html || true
inject frontend/index.html       || true
echo "✓ listo"
