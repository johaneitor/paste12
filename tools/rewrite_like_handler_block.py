#!/usr/bin/env python3
import re, sys, pathlib, shutil, py_compile, textwrap, traceback

W = pathlib.Path("wsgiapp/__init__.py")
if not W.exists():
    print("✗ wsgiapp/__init__.py no existe"); sys.exit(2)

def norm(s: str) -> str:
    s = s.replace("\r\n","\n").replace("\r","\n")
    if "\t" in s: s = s.replace("\t","    ")
    return s

src = norm(W.read_text(encoding="utf-8"))
lines = src.split("\n")
n = len(lines)

# Localiza el bloque:  (if|elif) action == "like":
like_pat = re.compile(r'^([ ]*)(?:elif|if)\s+action\s*==\s*(?P<q>["\'])like(?P=q)\s*:\s*$')
start = end = None
base_ws = ""

for i, L in enumerate(lines):
    m = like_pat.match(L)
    if m:
        start = i
        base_ws = m.group(1)
        break

if start is None:
    print("✗ No encontré bloque 'action == \"like\"'"); sys.exit(2)

# El final es la próxima cabecera al MISMO nivel base (elif/else/return/def/class) o EOF
hdr_same_lvl = re.compile(rf'^{re.escape(base_ws)}(elif\b|else\b|def\b|class\b|return\b)')
j = start + 1
while j < n:
    Lj = lines[j]
    if hdr_same_lvl.match(Lj):
        break
    j += 1
end = j  # no inclusivo

# Construye reemplazo canónico con la misma indentación base
body = textwrap.dedent("""
    try:
        from sqlalchemy import text as _text
        with _engine().begin() as cx:
            # Asegurar tabla e índice de dedupe (no-op si ya existen)
            try:
                cx.execute(_text(\"\"\"CREATE TABLE IF NOT EXISTS like_log(
                    note_id INTEGER NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                    fingerprint VARCHAR(128) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    PRIMARY KEY (note_id, fingerprint)
                )\"\"\"))
            except Exception:
                pass
            try:
                cx.execute(_text(\"\"\"CREATE UNIQUE INDEX IF NOT EXISTS uq_like_note_fp
                ON like_log(note_id, fingerprint)\"\"\"))
            except Exception:
                pass

            fp = _fingerprint(environ)
            inserted = False
            # Intentar insertar deduplicando por (note_id, fingerprint)
            try:
                cx.execute(
                    _text("INSERT INTO like_log(note_id, fingerprint, created_at) VALUES (:id,:fp, NOW())"),
                    {"id": note_id, "fp": fp}
                )
                inserted = True
            except Exception:
                inserted = False

            if inserted:
                cx.execute(
                    _text("UPDATE note SET likes = COALESCE(likes,0)+1 WHERE id=:id"),
                    {"id": note_id}
                )

            row = cx.execute(
                _text("SELECT COALESCE(likes,0), COALESCE(views,0), COALESCE(reports,0) FROM note WHERE id=:id"),
                {"id": note_id}
            ).first()
            likes  = int(row[0] or 0)
            views  = int(row[1] or 0)
            reports= int(row[2] or 0)

        code, payload = 200, {"ok": True, "id": note_id, "likes": likes, "views": views, "reports": reports, "deduped": (not inserted)}
    except Exception as e:
        code, payload = 500, {"ok": False, "error": str(e)}
""").strip("\n").split("\n")

# Re-indent al nivel base
body_indented = [ (base_ws + "    " + L if L else L) for L in body ]  # +4 espacios desde la cabecera 'if/elif ... like:'

new_lines = lines[:start+1] + body_indented + lines[end:]
out = "\n".join(new_lines)

# Backup + escribir
bak = W.with_suffix(".py.rewrite_like_block.bak")
if not bak.exists():
    shutil.copyfile(W, bak)
W.write_text(out, encoding="utf-8")
print(f"patched: bloque 'like' reescrito y normalizado | backup={bak.name}")

# Gate de compilación con ventana si falla
try:
    py_compile.compile(str(W), doraise=True)
    print("✓ py_compile OK")
except Exception as e:
    print("✗ py_compile falla:", e)
    tb = traceback.format_exc()
    m = re.search(r'__init__\\.py, line (\\d+)', tb)
    if m:
        ln = int(m.group(1))
        ctx = out.splitlines()
        a = max(1, ln-40); b = min(len(ctx), ln+40)
        print(f"\\n--- Ventana {a}-{b} ---")
        for k in range(a, b+1):
            print(f\"{k:5d}: {ctx[k-1]}\")
    sys.exit(1)
