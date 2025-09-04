#!/usr/bin/env python3
import pathlib, re, sys
P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")
if not re.search(r'^\s*import\s+os\b', s, re.M):
    s = re.sub(r'^(import[^\n]*\n|)', r'\1import os\n', s, count=1, flags=re.M)
    P.write_text(s, encoding="utf-8")
    print("patched: import os")
else:
    print("OK: import os ya presente")
