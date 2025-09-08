#!/usr/bin/env python3
import re, sys, pathlib

W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n").replace("\t","    ")
lines = s.split("\n")
n = len(lines)

def indw(l:str)->int: return len(l) - len(l.lstrip(" "))
def next_nonempty(i:int)->int:
    j = i+1
    while j < n and lines[j].strip()=="":
        j += 1
    return j

hdr = re.compile(r'^(except\b.*:|finally:|try:|else:|elif\b.*:)\s*$')

bad = []
for i, L in enumerate(lines):
    if hdr.match(L.lstrip()):
        base = indw(L)
        j = next_nonempty(i)
        if j >= n:
            bad.append((i+1, L.rstrip(), "<EOF>"))
            continue
        B = lines[j]
        if hdr.match(B.lstrip()) and indw(B) <= base:
            bad.append((i+1, L.rstrip(), f"{j+1}:{B.rstrip()}"))
            continue
        if indw(B) <= base:
            bad.append((i+1, L.rstrip(), f"{j+1}:{B.rstrip()}"))

if not bad:
    print("OK: sin headers con cuerpo mal indentado")
else:
    print("Headers con cuerpo incorrecto:")
    for ln, hdrline, body in bad:
        print(f"  L{ln}: {hdrline}  -> cuerpo {body}")
