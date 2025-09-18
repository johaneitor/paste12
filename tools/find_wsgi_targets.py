import os, importlib, inspect
ROOT=os.getcwd(); IGN={'.git','.venv','venv','__pycache__'}

def is_wsgi(obj):
    if not callable(obj): return False
    try:
        sig=inspect.signature(obj)
        names=[p.name.lower() for p in sig.parameters.values()
               if p.kind in (p.POSITIONAL_ONLY,p.POSITIONAL_OR_KEYWORD)]
        return len(names)>=2 and names[0] in ('environ','env') and 'start_response' in names[1]
    except Exception:
        return False

def maybe_factory(obj):
    if not callable(obj): return None
    try:
        sig=inspect.signature(obj)
        req=[p for p in sig.parameters.values()
             if p.kind in (p.POSITIONAL_ONLY,p.POSITIONAL_OR_KEYWORD)
             and p.default is inspect._empty]
        if len(req)==0:
            out=obj()
            return out if is_wsgi(out) else None
    except Exception:
        return None
    return None

def modname(path):
    rel=os.path.relpath(path,ROOT).split(os.sep)
    if rel[-1]=='__init__.py': rel=rel[:-1]
    else: rel[-1]=rel[-1].rsplit('.',1)[0]
    return ".".join([p for p in rel if p])

cands=[]
for dp, dns, fns in os.walk(ROOT):
    dns[:]=[d for d in dns if d not in IGN]
    for f in fns:
        if not f.endswith('.py'): continue
        if f in ('wsgi_entry.py',): continue
        mn=modname(os.path.join(dp,f))
        if not mn: continue
        try:
            m=importlib.import_module(mn)
        except Exception:
            continue
        # 1) WSGI directos
        for name in ('app','application','wsgi_app','inner_app'):
            if hasattr(m,name) and is_wsgi(getattr(m,name)):
                cands.append(f"{mn}:{name}")
        # 2) factorías sin args que devuelven WSGI
        for fac in ('create_app','make_app','build_app','get_app'):
            if hasattr(m,fac):
                out=maybe_factory(getattr(m,fac))
                if out and is_wsgi(out):
                    cands.append(f"{mn}:{fac}()")

seen=set(); out=[c for c in cands if not (c in seen or seen.add(c))]
print("NO CANDIDATES FOUND" if not out else "CANDIDATES:\n - "+"\n - ".join(out[:30]))
