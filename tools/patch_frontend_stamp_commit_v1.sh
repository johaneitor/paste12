#!/usr/bin/env bash
set -euo pipefail
SHA="$(git rev-parse HEAD)"
cands=( "backend/static/index.html" "static/index.html" "public/index.html" "index.html" "wsgiapp/templates/index.html" )
patched=0
for IDX in "${cands[@]}"; do
  [[ -f "$IDX" ]] || continue
  python - "$IDX" "$SHA" <<'PY'
import sys,re,io
p=sys.argv[1]; sha=sys.argv[2]
s=io.open(p,'r',encoding='utf-8').read()
if re.search(r'name=["\']p12-commit["\']', s, re.I):
    s=re.sub(r'(name=["\']p12-commit["\']\s+content=["\'])[0-9a-f]{7,40}(["\'])', r'\1'+sha+r'\2', s, flags=re.I)
else:
    s=re.sub(r'</head>', f'  <meta name="p12-commit" content="{sha}">\\n</head>', s, count=1, flags=re.I)
io.open(p,'w',encoding='utf-8').write(s)
print("STAMPED", p)
PY
  patched=$((patched+1))
done
if ! git diff --quiet; then git add -A; git commit -m "FE: stamp p12-commit=$(git rev-parse HEAD) en index"; fi
echo "Stamped $patched index.html file(s)."
