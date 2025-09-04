#!/usr/bin/env python3
import sys, pathlib, re, textwrap

if len(sys.argv) < 3:
    sys.stderr.write("Uso: append_patch_wrapper.py <nombre> <path_prefix>\n")
    sys.exit(2)

NAME = sys.argv[1]
PREFIX = sys.argv[2].rstrip("/")
SAFE = re.sub(r"[^0-9A-Za-z_]+", "_", NAME)
CLASS = f"_Patch_{SAFE}"
FLAG  = f"ENABLE_PATCH_{SAFE.upper()}"
GUARD = f"_PATCH_WRAPPED_{SAFE.upper()}"

P = pathlib.Path("wsgiapp/__init__.py")
s = P.read_text(encoding="utf-8")

begin = f"# === PATCH:{SAFE} BEGIN ==="
end   = f"# === PATCH:{SAFE} END ==="

if begin in s and end in s:
    print(f"OK: PATCH {SAFE} ya estaba (idempotente).")
else:
    block = textwrap.dedent(f"""
    {begin}
    # Parche encapsulado: apagado por defecto. Actívalo con {FLAG}=1
    class {CLASS}:
        def __init__(self, inner):
            self.inner = inner

        def _enabled(self, environ):
            val = (environ.get("{FLAG}") or "") or (environ.get("HTTP_{FLAG}") or "")
            return str(val).strip().lower() in ("1","true","yes","on")

        def __call__(self, environ, start_response):
            try:
                if not self._enabled(environ):
                    return self.inner(environ, start_response)
                path = (environ.get("PATH_INFO","") or "")
                # Encapsulación por prefijo exacto (no toca otras rutas)
                if path.startswith("{PREFIX}"):
                    # >>>>>>>>>>>>>>> ZONA DE PARCHE (edita aquí) <<<<<<<<<<<<<<<
                    # Por defecto, no hace nada: deja pasar tal cual.
                    # Ejemplo: podrías leer/reescribir headers o desviar a un handler específico.
                    # return tu_handler(environ, start_response)
                    # -----------------------------------------------------------
                    pass
            except Exception:
                # Pase seguro ante errores del parche
                pass
            return self.inner(environ, start_response)

    # Envolver una sola vez (outermost, reversible quitando este bloque)
    try:
        {GUARD}
    except NameError:
        try:
            app = {CLASS}(app)
        except Exception:
            pass
        {GUARD} = True
    {end}
    """).strip("\n") + "\n"

    s += "\n" + block
    P.write_text(s, encoding="utf-8")
    print(f"patched: {SAFE} ({PREFIX})")

