#!/usr/bin/env python3
import sys, importlib

def main():
    try:
        m = importlib.import_module("wsgiapp")
    except Exception as e:
        print("✗ import wsgiapp falló:", repr(e)); sys.exit(2)
    has = hasattr(m, "app")
    print("wsgiapp importado. app presente?:", has)
    if has:
        print("type(app):", type(getattr(m, "app")))
    else:
        print("Sugerencia: reparar epílogo WSGI (app = _middleware(...))")
        sys.exit(1)

if __name__ == "__main__":
    main()
