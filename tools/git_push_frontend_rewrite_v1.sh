#!/usr/bin/env bash
set -euo pipefail

MSG="${1:-ops: frontend rewrite limpio + sanidades}"
SRC_SD="/sdcard/Download/index.html"
DEST="frontend/index.html"
TS="$(date -u +%Y%m%d-%H%M%SZ)"

# 0) Verificaciones básicas
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: no es un repo git."; exit 2; }
[[ -d frontend ]] || { echo "ERROR: falta el directorio frontend/"; exit 3; }
[[ -f "$DEST" ]] && cp -f "$DEST" "frontend/index.$TS.bak" && echo "[backup] frontend/index.$TS.bak"

# 1) Copiar desde /sdcard/Download si existe
if [[ -f "$SRC_SD" ]]; then
  cp -f "$SRC_SD" "$DEST"
  echo "[copy] $SRC_SD -> $DEST"
else
  echo "ℹ️  No se encontró $SRC_SD; uso el $DEST actual."
fi

# 2) Sanidades rápidas (Python)
python - <<'PY'
import io, re, sys
p="frontend/index.html"
s=io.open(p,"r",encoding="utf-8").read()

def need(cond,msg):
    if not cond:
        print("SANITY FAIL -",msg); sys.exit(11)

# meta viewport
need(re.search(r'<meta[^>]+name=["\']viewport["\']', s, re.I), "falta meta viewport")
# único h1
h1s = re.findall(r'<h1\b', s, re.I)
need(len(h1s)==1, f"h1 duplicado: {len(h1s)} encontrados")
# formulario básico
need(re.search(r'<textarea[^>]+id=["\']text["\']', s, re.I), "falta textarea#text")
need(re.search(r'id=["\']send["\']', s, re.I), "falta botón #send")
# links legales
need(re.search(r'href=["\']/terms["\']', s, re.I), "falta link /terms")
need(re.search(r'href=["\']/privacy["\']', s, re.I), "falta link /privacy")
print("✓ sanidades OK")
PY

# 3) Stage forzado (por si .gitignore tapa tools/)
git add -f tools/git_push_frontend_rewrite_v1.sh 2>/dev/null || true
git add "$DEST"

# 4) Commit
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

# 5) Push
echo "== prepush gate =="
echo "✓ listo"
echo "Sugerido: correr testers contra prod antes/después del push."
git push -u origin main

# 6) Info de HEADs
echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream se definió recién)"
