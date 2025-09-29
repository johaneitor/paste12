#!/usr/bin/env python3
import re, sys, os, hashlib, time, io
EXTS={'.py','.js','.ts','.jsx','.tsx','.html','.css'}
SKIP=('node_modules','venv','.git')
ROOTS=['wsgiapp','static','public','templates','.']
def iter_files():
    seen=set()
    for root in ROOTS:
        if not os.path.isdir(root): continue
        for dirpath,_,files in os.walk(root):
            if any(x in dirpath for x in SKIP): continue
            for f in files:
                ext=os.path.splitext(f)[1].lower()
                if ext in EXTS:
                    p=os.path.join(dirpath,f)
                    if p in seen: continue
                    seen.add(p); yield p
def normalize(code,ext):
    s=code
    if ext in ('.js','.ts','.jsx','.tsx'):
        s=re.sub(r'//.*','',s); s=re.sub(r'/\*.*?\*/','',s,flags=re.S)
    if ext=='.py':
        s=re.sub(r'#.*','',s)
    if ext in ('.html','.css'):
        s=re.sub(r'<!--.*?-->','',s,flags=re.S)
    lines=[re.sub(r'\s+',' ',ln).strip() for ln in s.splitlines()]
    return [ln for ln in lines if ln]
def shingles(lines,k=8):
    for i in range(0, max(0,len(lines)-k+1)):
        block='\n'.join(lines[i:i+k])
        h=hashlib.sha1(block.encode()).hexdigest()
        yield i,h,block
def main(outpath):
    index={}; meta={}
    for p in iter_files():
        ext=os.path.splitext(p)[1].lower()
        try:
            with io.open(p,'r',encoding='utf-8',errors='ignore') as f:
                lines=normalize(f.read(),ext)
        except Exception:
            continue
        meta[p]=len(lines)
        for i,h,blk in shingles(lines):
            index.setdefault(h,[]).append((p,i,blk))
    dup=[]
    for h,occ in index.items():
        files=set(o[0] for o in occ)
        if len(files)>=2:
            dup.append((h,occ))
    dup.sort(key=lambda x:(-len(x[1]), x[1][0][0]))
    os.makedirs(os.path.dirname(outpath), exist_ok=True)
    with io.open(outpath,'w',encoding='utf-8') as w:
        w.write("# Clones/duplicados por shingles (k=8)\n")
        w.write(f"# Archivos analizados: {len(meta)}\n")
        if not dup:
            w.write("\n(no se hallaron clones cruzados)\n")
            return
        for h,occ in dup[:200]:
            w.write("\n--- DUPLICADO ---\n")
            for (p,i,blk) in occ:
                w.write(f"{p}:{i+1}\n")
            w.write(">>> fragmento normalizado >>>\n")
            w.write(occ[0][2]+"\n")
if __name__=='__main__':
    out=sys.argv[1]
    main(out)
