#!/usr/bin/env python3
import re, sys, pathlib, py_compile
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
changed = False

# Asegurar imports mínimos
for mod in ("os","json","hashlib"):
    if not re.search(rf'^\s*import\s+{mod}\b', s, re.M):
        s = f"import {mod}\n{s}"
        changed = True

# Reemplazar método _fp dentro de _LikesGuardV3
pat = re.compile(r'(class\s+_LikesGuardV3\b.*?\n)(\s+)def\s+_fp\(\s*self,\s*environ\)\s*:\n(?:.*?\n){1,60}?(\2def\s+_json\b)', re.S)
def repl(m):
    indent = m.group(2)
    body = f"""{indent}def _fp(self, environ):
{indent}    # 0) explícito
{indent}    fp = (environ.get("HTTP_X_FP") or "").strip()
{indent}    if fp:
{indent}        return fp[:128]
{indent}    # 1) IPs “reales” comunes detrás de proxies/CDN
{indent}    candidates = [
{indent}        (environ.get("HTTP_CF_CONNECTING_IP") or "").strip(),
{indent}        (environ.get("HTTP_TRUE_CLIENT_IP") or "").strip(),
{indent}        (environ.get("HTTP_X_REAL_IP") or "").strip(),
{indent}    ]
{indent}    xff = (environ.get("HTTP_X_FORWARDED_FOR") or "")
{indent}    if xff:
{indent}        candidates.append(xff.split(",")[0].strip())
{indent}    candidates.append((environ.get("REMOTE_ADDR") or "").strip())
{indent}    ip = next((c for c in candidates if c), "")
{indent}    ua = (environ.get("HTTP_USER_AGENT") or "").strip()
{indent}    raw = f"{'{'}ip{'}'}|{'{'}ua{'}'}".encode("utf-8","ignore")
{indent}    import hashlib
{indent}    return hashlib.sha256(raw).hexdigest()
"""
    return m.group(1)+body+m.group(3)

new, n = pat.subn(repl, s, count=1)
if n:
    s = new; changed = True

if not changed:
    print("OK: _LikesGuardV3 ya tenía imports/_fp robusto"); sys.exit(0)

P.write_text(s, encoding="utf-8")
py_compile.compile(str(P), doraise=True)
print("patched: _LikesGuardV3._fp (CF-aware) + imports")
