#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile
W = pathlib.Path("wsgiapp/__init__.py")
s = W.read_text(encoding="utf-8").replace("\r\n","\n").replace("\r","\n")

# limitar el alcance al segmento que contiene 'CREATE TABLE IF NOT EXISTS like_log(' hasta 'fp = _fingerprint('
a = s.find("CREATE TABLE IF NOT EXISTS like_log(")
b = s.find("fp = _fingerprint(", a if a!=-1 else 0)
if a!=-1 and b!=-1:
    seg = s[a:b]
    # eliminar patrones triviales: 'try:\n    pass\nexcept Exception:\n    pass' sin código entre medio
    seg2 = re.sub(
        r'([ \t]*)try:\n\1[ \t]{4}pass\n\1except\s+Exception:\s*\n\1[ \t]{4}pass\n',
        '',
        seg
    )
    if seg2 != seg:
        news = s[:a] + seg2 + s[b:]
        bak = W.with_suffix(".py.clean_try_pass_like_log.bak")
        if not bak.exists():
            shutil.copyfile(W, bak)
        W.write_text(news, encoding="utf-8")
        print("patched: try/pass triviales removidos en bloque like_log | backup=", bak.name)
        py_compile.compile(str(W), doraise=True)
        print("✓ py_compile OK")
    else:
        print("OK: no try/pass triviales en like_log")
else:
    print("OK: no segmento like_log acotado encontrado")
