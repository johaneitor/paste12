#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-}"
if [[ -z "$OUTDIR" ]]; then
  for d in "$HOME/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download" "$HOME/Download"; do
    [[ -d "$d" && -w "$d" ]] && OUTDIR="$d" && break
  done
fi
mkdir -p "$OUTDIR"
TS="$(date -u +%Y%m%d-%H%M%SZ)"
R="$OUTDIR/repo-audit-$TS.txt"

{
echo "== GIT STATUS =="; git status --porcelain=v1
echo; echo "== GIT BRANCH =="; git branch --show-current; git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "(sin upstream)"
echo; echo "== GIT DIFF (resumen) =="; git diff --stat || true
echo; echo "== GIT STASH LIST =="; git stash list || true
echo; echo "== CONFLICT MARKERS ==";
grep -RInE '^(<<<<<<<|=======|>>>>>>>)' --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=venv . || echo "(sin marcadores)"
echo; echo "== PY COMPILE (wsgiapp/__init__.py) =="; python -m py_compile wsgiapp/__init__.py && echo "OK py_compile" || echo "ERROR py_compile"
idx="$(grep -RIl --include='*.html' -e '<meta name=\"p12-commit\"' -e '<title' static public templates wsgiapp . 2>/dev/null | head -n1 || true)"
echo; echo "== FRONTEND INDEX =="; echo "index: ${idx:-no encontrado}"
if [[ -n "${idx:-}" && -f "$idx" ]]; then
  echo "p12-commit: $(grep -i 'name=\"p12-commit\"' "$idx" || echo no)"
  echo "p12-safe-shim: $(grep -i 'p12-safe-shim' "$idx" || echo no)"
  echo "single(meta): $(grep -i 'name=\"p12-single\"' "$idx" || echo no)"
  echo "single(body): $(grep -i '<body[^>]*data-single=' "$idx" || echo no)"
fi
echo; echo "== BACKEND HELPERS (una línea?) =="
grep -nE 'def _[a-zA-Z0-9_]+\([^)]*\):\s*[^#\n]+' wsgiapp/__init__.py || echo "(sin defs en línea)"
echo; echo "== ENDPOINTS like/view/report referencian helper? =="
grep -nE 'def (like|view|report)\(' wsgiapp/__init__.py || true
grep -nE '_p12_bump_counter|_bump_counter' wsgiapp/__init__.py || echo "(helper no referenciado)"
} | tee "$R" >/dev/null
echo "Reporte: $R"
