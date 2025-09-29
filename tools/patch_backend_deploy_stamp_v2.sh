#!/usr/bin/env bash
set -euo pipefail
python - <<'PY'
import os,re,json,py_compile,shutil,time
from pathlib import Path
p=Path("wsgiapp/__init__.py"); s=p.read_text(encoding="utf-8")
TS=time.strftime("%Y%m%d-%H%M%SZ")
def add_import(s,mod):
    return ("import "+mod+"\n"+s) if re.search(rf'^\s*import\s+{mod}\b',s,re.M) is None else s
for m in ("os","re","json"): s=add_import(s,m)
if 'def deploy_stamp' not in s or '/api/deploy-stamp' not in s:
    s += '''
# --- paste12: /api/deploy-stamp ---
def _p12_guess_commit():
    for k in ("RENDER_GIT_COMMIT","GIT_COMMIT","SOURCE_COMMIT","COMMIT_SHA","GAE_GIT_COMMIT"):
        v=os.environ.get(k)
        if v and re.fullmatch(r"[0-9a-f]{7,40}", v): return {"commit": v, "source":"env:"+k}
    for idx in ("backend/static/index.html","static/index.html","public/index.html","index.html"):
        try:
            with open(idx,"r",encoding="utf-8") as f:
                m=re.search(r'name="p12-commit" content="([0-9a-f]{7,40})"', f.read(), re.I)
                if m: return {"commit": m.group(1), "source":"index:"+idx}
        except Exception: pass
    return None

def deploy_stamp():
    info=_p12_guess_commit()
    if not info:
        return (json.dumps({"error":"not_found"}), 404, {"Content-Type":"application/json"})
    return (json.dumps(info), 200, {"Content-Type":"application/json"})
'''
    bak=p.with_name(f"__init__.py.bak-deploystamp-{TS}")
    shutil.copy2(p,bak)
    p.write_text(s,encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("PATCH_OK", bak.name)
else:
    print("ALREADY_PRESENT")
PY
git add wsgiapp/__init__.py wsgiapp/__init__.py.bak-* || true
git commit -m "api: /api/deploy-stamp (commit autodetect env/index) [p12]" || true
