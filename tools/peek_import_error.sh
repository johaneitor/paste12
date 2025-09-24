#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-https://paste12-rmsk.onrender.com}"
echo "== peek import error @ $BASE =="
tmp="$(mktemp)"
code="$(curl -sS -o "$tmp" -w '%{http_code}' "$BASE/__api_import_error" || true)"
echo "status=$code"
if [[ "$code" != "200" ]]; then
  echo "(no JSON; primeros bytes)"; head -c 600 "$tmp" || true; echo; exit 0
fi
python - <<'PY' "$tmp" || true
import sys,json,re, pathlib
raw = pathlib.Path(sys.argv[1]).read_text()
try:
  j = json.loads(raw)
except Exception as e:
  print("(no JSON parseable)", e)
  print(raw[:600])
  raise SystemExit(0)
tb = j.get("traceback","")
m  = re.search(r'File "([^"]+)", line (\d+)', tb)
print("-- parsed --")
if m:
  print(m.group(1), m.group(2))
  print()
  print(j.get("error",""))
else:
  print("(no file/line found)")
PY
