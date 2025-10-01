#!/usr/bin/env python3
import sys, re, hashlib, io
def norm(s):
    s = re.sub(r'<meta\s+name=["\']p12-commit["\'][^>]*>', '', s, flags=re.I)
    s = re.sub(r'\s+', ' ', s).strip()
    return s
def sha(s): return hashlib.sha256(s.encode('utf-8', 'ignore')).hexdigest()
if len(sys.argv) != 3:
    print("Uso: html_compare_ignore_commit_v1.py REMOTE.html LOCAL.html", file=sys.stderr); sys.exit(2)
A = norm(io.open(sys.argv[1], 'r', encoding='utf-8', errors='ignore').read())
B = norm(io.open(sys.argv[2], 'r', encoding='utf-8', errors='ignore').read())
ha, hb = sha(A), sha(B)
eq = (ha == hb)
print(f"index_equal_ignoring_commit: {'yes' if eq else 'no'}")
print(f"sha_remote_norm: {ha}")
print(f"sha_local_norm : {hb}")
sys.exit(0 if eq else 1)
