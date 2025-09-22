# Gunicorn entrypoint
from contract_shim import application, app  # reexport
# --- Paste12 Contract Shim hook (v10) ---
try:
    from contract_shim import wrap_app_for_p12
    if 'application' in globals():
        application = wrap_app_for_p12(application)
except Exception as _e:
    # nunca romper arranque
    pass
# --- end shim hook ---
