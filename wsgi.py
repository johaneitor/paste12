# Minimal, robust WSGI entry point for Render
# Tries 'application' first, falls back to 'app' from contract_shim.
import os
try:
    from contract_shim import application  # type: ignore
    app = application  # alias
except Exception:
    from contract_shim import app as application  # type: ignore
    app = application

# Optional AdSense injection (if adsense_injector.py is present)
try:
    from adsense_injector import install_adsense_injector  # type: ignore
    install_adsense_injector(application, os.environ.get("ADSENSE_CLIENT","ca-pub-9479870293204581"))
except Exception:
    # In production keep going even if injector isn't available
    pass
