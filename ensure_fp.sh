#!/usr/bin/env bash
set -Eeuo pipefail
python - <<'PY'
from pathlib import Path, re
p = Path('backend/routes.py')
s = p.read_text(encoding='utf-8')

changed = False

# Inserta helper _real_ip() si falta
if 'def _real_ip' not in s:
    s = s.replace('def _fp()', '''def _real_ip():
    h = request.headers
    xff = (h.get("X-Forwarded-For") or "").strip()
    if xff:
        return xff.split(",")[0].strip()
    cip = h.get("CF-Connecting-IP")
    if cip:
        return cip.strip()
    return request.remote_addr or "anon"

def _fp()''')
    changed = True

# Normaliza _fp() para priorizar header/cookie y caer a _real_ip()
s2 = re.sub(
    r'def _fp\([^\)]*\):[\s\S]*?(?=\n\n|\r\n\r\n|def\s)',
    '''def _fp():
    h = request.headers
    return (
        h.get("X-Client-Fingerprint")
        or h.get("X-User-Token")
        or request.cookies.get("p12_fp")
        or request.cookies.get("fp")
        or _real_ip()
    )
''',
    s, flags=re.S
)
if s2 != s:
    s = s2; changed = True

if changed:
    p.write_text(s, encoding='utf-8')
    print("✓ routes.py actualizado (_fp/_real_ip).")
else:
    print("• routes.py ya estaba OK.")
PY
