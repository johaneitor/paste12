#!/usr/bin/env bash
set -euo pipefail

python - <<'PY'
import os, re, json, py_compile
p="wsgiapp/__init__.py"
s=open(p,"r",encoding="utf-8").read()

needs=os.environ.get("P12_FORCE_PATCH", "1")=="1"
if 'def deploy_stamp' not in s or '/api/deploy-stamp' not in s:
    if "import os" not in s: s="import os\n"+s
    if "import re" not in s: s="import re\n"+s
    if "import json" not in s: s="import json\n"+s
    s += r"""

# --- paste12: deploy-stamp endpoint ---
def _p12_guess_commit():
    # 1) env vars típicas de plataformas
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA","GAE_GIT_COMMIT"):
        v=os.environ.get(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v):
            return {"commit": v, "source":"env:"+k}
    # 2) parsear index en disco (estático)
    for idx in ("backend/static/index.html","static/index.html","public/index.html","index.html"):
        try:
            with open(idx,"r",encoding="utf-8") as f:
                m=re.search(r'name="p12-commit" content="([0-9a-f]{7,40})"', f.read(), re.I)
                if m: return {"commit": m.group(1), "source":"index:"+idx}
        except Exception:
            pass
    return None

def deploy_stamp():
    info=_p12_guess_commit()
    if not info:
        # mantener semántica 404 si no podemos determinar el commit
        body=json.dumps({"error":"not_found"})
        return (body, 404, {"Content-Type":"application/json"})
    body=json.dumps(info)
    return (body, 200, {"Content-Type":"application/json"})
"""
    # si tu router usa add_url_rule o similar, acá solo devolvemos WSGI-style tuple
    open(p,"w",encoding="utf-8").write(s)
    py_compile.compile(p, doraise=True)
    print("PATCH_OK")
else:
    print("ALREADY_PRESENT")

PY

git add wsgiapp/__init__.py
git commit -m "api: add /api/deploy-stamp (commit autodetect env/index) [p12]" || true
git push
