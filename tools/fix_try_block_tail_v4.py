#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(text:str)->str:
    text = text.replace("\r\n","\n").replace("\r","\n")
    if "\t" in text: text = text.replace("\t","    ")
    return text

def mark_triple_zones(lines):
    zones = [False]*len(lines)
    in_triple = False
    quote = None
    qpat = re.compile(r'(?<!\\)(?P<q>"""|\'\'\')')
    for i, ln in enumerate(lines):
        for m in qpat.finditer(ln):
            q = m.group('q')
            if not in_triple:
                in_triple = True; quote = q
            else:
                if q == quote:
                    in_triple = False; quote = None
        zones[i] = in_triple
    return zones

def indw(s:str)->int:
    return len(s) - len(s.lstrip(" "))

def compile_or_window():
    try:
        py_compile.compile(str(W), doraise=True)
        return True, None
    except Exception as e:
        tb = traceback.format_exc()
        m = re.search(r'__init__\.py, line (\d+)', tb)
        ln = int(m.group(1)) if m else None
        return False, (e, ln)

def inject_except_once(target_ln:int)->bool:
    """Busca el try: que cubre la línea target_ln y añade except/pass si falta."""
    raw = W.read_text(encoding="utf-8")
    s = norm(raw)
    lines = s.split("\n")
    n = len(lines)
    zones = mark_triple_zones(lines)

    idx = max(0, target_ln-1)
    # subir hasta encontrar un try: top-level relativo al bloque (no en triple-string)
    t = idx
    found_try = None
    while t >= 0:
        if not zones[t] and re.match(r'^([ ]*)try:\s*$', lines[t]):
            found_try = t
            break
        t -= 1
    if found_try is None:
        return False

    base = re.match(r'^([ ]*)try:\s*$', lines[found_try]).group(1)
    base_w = len(base)

    # saltar líneas en blanco tras el try
    j = found_try + 1
    while j < n and lines[j].strip() == "":
        j += 1

    # avanzar dentro del cuerpo hasta dedentar a <= base
    k = j
    has_ex_or_fin = False
    while k < n:
        if zones[k]:
            k += 1; continue
        cur = lines[k]
        curw = indw(cur)
        if curw == base_w and re.match(r'^(except\b|finally\b)', cur.lstrip()):
            has_ex_or_fin = True
            break
        if cur.strip() != "" and curw <= base_w:
            break
        k += 1

    if has_ex_or_fin:
        return False  # ese try ya estaba bien

    # insertar except/pass antes de dedentar (línea k)
    ins_idx = k
    lines.insert(ins_idx, base + "except Exception:")
    lines.insert(ins_idx+1, base + "    pass")

    out = "\n".join(lines)
    if out != s:
        bak = W.with_suffix(".py.fix_try_tail_v4.bak")
        if not bak.exists():
            shutil.copyfile(W, bak)
        W.write_text(out, encoding="utf-8")
        return True
    return False

# ——— Loop de reparación hasta compilar o sin progreso ———
changed_any = False
for _ in range(12):
    ok, info = compile_or_window()
    if ok:
        print("✓ py_compile OK")
        if changed_any:
            print("Arreglo aplicado (try→except) y compilación estable.")
        else:
            print("No había que arreglar (ya compilaba).")
        sys.exit(0)
    err, ln = info
    if ln is None:
        print("✗ py_compile falla (sin línea detectable):", err)
        break
    print(f"detectado fallo en línea {ln}: intentaremos inyectar except/pass…")
    if not inject_except_once(ln):
        print("✗ No se pudo inyectar except/pass en esa zona. Mostrando ventana…")
        # Ventana de contexto
        s_now = norm(W.read_text(encoding="utf-8"))
        L = s_now.split("\n")
        start = max(1, ln-25); end = min(len(L), ln+25)
        for k in range(start, end+1):
            print(f"{k:5d}: {L[k-1]}")
        sys.exit(1)
    changed_any = True

# Si salimos del loop sin compilar
print("✗ No se logró compilar tras múltiples pasadas.")
ok, info = compile_or_window()
if not ok:
    err, ln = info
    print("Último error:", err)
    if ln:
        s_now = norm(W.read_text(encoding="utf-8"))
        L = s_now.split("\n")
        start = max(1, ln-25); end = min(len(L), ln+25)
        print(f"\n--- Ventana {start}-{end} ---")
        for k in range(start, end+1):
            print(f"{k:5d}: {L[k-1]}")
sys.exit(1)
