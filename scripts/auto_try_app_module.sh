set -euo pipefail
cands=( "wsgiapp:app" "render_entry:app" "entry_main:app" "run:app" "run:create_app()" )
for c in "${cands[@]}"; do
  if python - "$c" <<'PY' 2>/dev/null; then
    echo "$c"
    exit 0
  fi
import sys, importlib
spec = sys.argv[1]
if ":" in spec:
    mod, attr = spec.split(":",1)
else:
    mod, attr = spec, "app"
m = importlib.import_module(mod)
if attr.endswith("()"):
    fn = getattr(m, attr[:-2])
    app = fn()
else:
    app = getattr(m, attr)
assert app is not None
PY
done
exit 1
