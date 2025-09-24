#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-${1:-https://paste12-rmsk.onrender.com}}"
MSG="${MSG:-${2:-ops: backend hotfixes + tools (push+sanity)}}"
OUT="${OUT:-/sdcard/Download}"

echo "== gates (bash) =="
for f in tools/*.sh; do
  [[ -f "$f" ]] && bash -n "$f" || true
done

echo "== gates (py_compile) =="
py_err=0
for py in contract_shim.py wsgi.py backend/__init__.py backend/app.py backend/main.py backend/wsgi.py run.py; do
  [[ -f "$py" ]] && python -m py_compile "$py" || py_err=1
done
if [[ "$py_err" -ne 0 ]]; then
  echo "py_compile FAIL (corrige lo de arriba)"; exit 2
fi

echo "== stage (forzado por .gitignore) =="
git add -f tools/*.sh 2>/dev/null || true
git add contract_shim.py wsgi.py 2>/dev/null || true
git add backend/*.py 2>/dev/null || true
git add frontend/*.html 2>/dev/null || true

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "$MSG"
else
  echo "ℹ️  Nada para commitear"
fi

echo "== push =="
git push -u origin main

echo "== HEADs =="
echo "Local : $(git rev-parse HEAD)"
UP="$(git rev-parse @{u} 2>/dev/null || true)"
[[ -n "$UP" ]] && echo "Remote: $UP" || echo "Remote: (upstream creado)"

echo "== smoke (post-push, contra BASE) =="
mkdir -p "$OUT"
if [[ -x tools/smoke_after_cors_wsgi_fix_v2.sh ]]; then
  tools/smoke_after_cors_wsgi_fix_v2.sh "$BASE" "$OUT"
elif [[ -x tools/smoke_after_wsgi_fix_v1.sh ]]; then
  tools/smoke_after_wsgi_fix_v1.sh "$BASE" "$OUT"
else
  echo "No encontré smoke_*; hago uno mínimo:"
  ts="$(date -u +%Y%m%d-%H%M%SZ)"
  curl -fsS "$BASE/api/health" -o "$OUT/health-$ts.json" || true
  curl -fsS -I -X OPTIONS "$BASE/api/notes" -o "$OUT/options-$ts.txt" || true
  curl -fsS -D "$OUT/api-notes-h-$ts.txt" -o "$OUT/api-notes-b-$ts.json" "$BASE/api/notes?limit=5" || true
  echo "Archivos en $OUT:"; ls -1 "$OUT" | tail -n 10
fi

echo "== Siguiente paso en Render =="
echo "  - Clear build cache + Deploy"
echo "  - Start Command:"
echo "    gunicorn wsgi:application --chdir /opt/render/project/src -w \${WEB_CONCURRENCY:-2} -k gthread --threads \${THREADS:-4} --timeout \${TIMEOUT:-120} -b 0.0.0.0:\$PORT"
