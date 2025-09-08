#!/usr/bin/env python3
import re, pathlib, sys
p = pathlib.Path("wsgiapp/__init__.py")
s = p.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
lines = s.split("\n")
def indw(x): return len(x)-len(x.lstrip(" "))
bad = []
i=0; n=len(lines)
while i<n:
  m = re.match(r'^([ ]*)try:\s*$', lines[i])
  if not m: i+=1; continue
  base = len(m.group(1))
  j=i+1
  while j<n and lines[j].strip()=="": j+=1
  k=j
  ok=False
  while k<n:
    cur = lines[k]; w = indw(cur)
    if cur.strip()=="":
      k+=1; continue
    if w==base and re.match(r'^(except\b|finally\b)', cur.lstrip()):
      ok=True; break
    if w<=base:
      break
    k+=1
  if not ok: bad.append(i+1)
  i=k+1
if bad:
  print("Bare try sin handler en líneas:", ", ".join(map(str,bad))); sys.exit(2)
print("OK: todos los try tienen handler")
