#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py"); s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")
if "\t" in s: s = s.replace("\t","    ")
lines = s.split("\n"); n=len(lines); ch=False
hdr = re.compile(r'^([ ]*)(except\b.*:|finally:|else:|elif\b.*:)\s*$')
def nn(i):
    j=i+1
    while j<n and lines[j].strip()=="":
        j+=1
    return j
i=0
while i<n:
    m = hdr.match(lines[i])
    if not m: i+=1; continue
    base=len(m.group(1))
    j=nn(i)
    if j>=n or re.match(r'^(except|finally|else:|elif\b)', lines[j].lstrip()) and (len(lines[j])-len(lines[j].lstrip())<=base):
        lines.insert(j," "*(base+4)+"pass"); n+=1; ch=True; i=j+1; continue
    if (len(lines[j])-len(lines[j].lstrip()))<=base:
        lines[j]=" "*(base+4)+lines[j].lstrip(); ch=True; i=j+1; continue
    i=j
out="\n".join(lines)
if ch:
    bak=W.with_suffix(".py.fix_any_block_header_body.bak")
    import shutil; 
    if not bak.exists(): shutil.copyfile(W,bak)
    W.write_text(out,encoding="utf-8"); print("patched: headers con cuerpo arreglados | backup=",bak.name)
py_compile.compile(str(W), doraise=True); print("✓ py_compile OK")
