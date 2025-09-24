#!/usr/bin/env bash
set -euo pipefail
F="render_entry.py"
grep -q '@api.get("/version")' "$F" 2>/dev/null && { echo "[i] /api/version ya existe."; exit 0; }
awk '
  {print}
  /^api = Blueprint\(/ && !added {
    added=1
    print ""
    print "@api.get(\"/version\")"
    print "def version():"
    print "    import os"
    print "    sha = os.environ.get(\"RENDER_GIT_COMMIT\") or os.environ.get(\"GIT_COMMIT\") or \"unknown\""
    print "    return jsonify(ok=True, commit=sha), 200"
    print ""
  }
' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
python -m py_compile "$F"
echo "[ok] /api/version añadido"
