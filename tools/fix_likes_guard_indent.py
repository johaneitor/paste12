#!/usr/bin/env python3
import re, sys, pathlib, py_compile

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8").replace("\t", "    ")  # normaliza tabs→espacios

# Localiza la clase de likes (acepta _LikesGuard o _LikesWrapper)
m_cls = re.search(r'(?m)^(?P<cind>\s*)class\s+(?:_LikesGuard|_LikesWrapper)\s*:\s*$', s)
if not m_cls:
    print("No encontré class _LikesGuard/_LikesWrapper; nada que arreglar")
    sys.exit(0)

class_indent = m_cls.group('cind')
ci = len(class_indent)
# Defs dentro de clase deben tener indent = class_indent + 4
def_indent = " " * (ci + 4)

# Buscar la línea 'def __call__(self, environ, start_response):' con la indentación esperada
pat_call = re.compile(rf'(?m)^{re.escape(def_indent)}def\s+__call__\s*\(\s*self\s*,\s*environ\s*,\s*start_response\s*\)\s*:\s*$')
m_call = pat_call.search(s, pos=m_cls.end())
if not m_call:
    print("No encontré def __call__ con indent esperado; nada que arreglar")
    sys.exit(0)

# Detectar el final del método __call__ escaneando líneas hasta próximo 'def ' al mismo indent o fin de clase
start_body = m_call.end()
lines = s[start_body:].splitlines(keepends=True)

def line_indent_spaces(line: str) -> int:
    return len(line) - len(line.lstrip(" "))

end_off = 0
for i, ln in enumerate(lines):
    # Fin del método si aparece otro 'def' al mismo indent dentro de la clase
    if ln.lstrip().startswith("def ") and line_indent_spaces(ln) == (ci + 4):
        break
    # Fin de clase si volvemos al indent del class o menor con línea no vacía
    if ln.strip() and line_indent_spaces(ln) <= ci and not ln.lstrip().startswith("#"):
        break
    end_off += len(ln)
else:
    end_off = sum(map(len, lines))

# Construir cuerpo nuevo con indent correcto (un nivel más que def)
b = def_indent + "    "
new_body = (
    f"{b}try:\n"
    f"{b}    path = (environ.get('PATH_INFO','') or '')\n"
    f"{b}    method = (environ.get('REQUEST_METHOD','GET') or 'GET').upper()\n"
    f"{b}    if method == 'POST':\n"
    f"{b}        mid = None\n"
    f"{b}        if path.startswith('/api/notes/') and path.endswith('/like'):\n"
    f"{b}            mid = path[len('/api/notes/'):-len('/like')]\n"
    f"{b}        elif path.startswith('/api/like/'):\n"
    f"{b}            mid = path[len('/api/like/'):]\n"
    f"{b}        if mid:\n"
    f"{b}            try:\n"
    f"{b}                note_id = int(mid.strip('/'))\n"
    f"{b}            except Exception:\n"
    f"{b}                note_id = None\n"
    f"{b}            else:\n"
    f"{b}                if note_id:\n"
    f"{b}                    return self._handle_like(environ, start_response, note_id)\n"
    f"{b}except Exception:\n"
    f"{b}    pass\n"
    f"{b}return self.inner(environ, start_response)\n"
)

s2 = s[:start_body] + new_body + s[start_body + end_off:]
P.write_text(s2, encoding="utf-8")

# Verificación de sintaxis del módulo
py_compile.compile(str(P), doraise=True)
print("OK: __call__ reparado (indent consistente) y módulo compila")
