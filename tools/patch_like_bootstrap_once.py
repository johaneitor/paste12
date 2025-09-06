#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8")
orig = s
changed = False

# Sentinel + lock (si no existe)
if "_LIKE_LOG_BOOTSTRAPPED" not in s:
    ins = """
# -- like_log bootstrap sentinel (one-time) --
try:
    _LIKE_LOG_BOOTSTRAPPED
except NameError:
    _LIKE_LOG_BOOTSTRAPPED = False
    import threading as _LIKETH
    _LIKE_BOOTSTRAP_LOCK = _LIKETH.Lock()
"""
    s = s + ("\n" if not s.endswith("\n") else "") + ins
    changed = True

# Asegurar alias T = _text (por si falta)
if not re.search(r'(?m)^\s*from\s+sqlalchemy\s+import\s+text\s+as\s+_text\s*$', s):
    s = s + "\nfrom sqlalchemy import text as _text\n"
    changed = True
if not re.search(r'(?m)^\s*T\s*=\s*_text\s*$', s):
    s = s + "\nT = _text\n"
    changed = True

# Reemplazar _bootstrap_like para usar lock + sentinel
pat = re.compile(r'(?ms)def\s+_bootstrap_like\(\s*self\s*,\s*cx\s*\):.*?^\s*def\s', re.S)
def repl(m):
    return """def _bootstrap_like(self, cx):
        global _LIKE_LOG_BOOTSTRAPPED
        if _LIKE_LOG_BOOTSTRAPPED:
            return
        with _LIKE_BOOTSTRAP_LOCK:
            if _LIKE_LOG_BOOTSTRAPPED:
                return
            try:
                cx.execute(T(\"\"\"
CREATE TABLE IF NOT EXISTS like_log(
  note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
  fingerprint VARCHAR(128) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (note_id, fingerprint)
)
\"\"\"))
            except Exception:
                pass
            try:
                cx.execute(T(\"\"\"
CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
ON like_log(note_id, fingerprint)
\"\"\")) 
            except Exception:
                pass
            _LIKE_LOG_BOOTSTRAPPED = True

    def """.replace('\r','')
s2, n = pat.subn(repl, s, count=1)
if n:
    s = s2; changed = True

if not changed:
    print("OK: nada que cambiar"); sys.exit(0)

bak = W.with_suffix(".py.like_bootstrap_once.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("patched: like_log bootstrap once (con lock); backup:", bak.name)
