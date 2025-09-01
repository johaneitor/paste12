import os
from waitress import serve
import patched_app as pa
serve(pa.app, host="0.0.0.0", port=int(os.environ.get("PORT","8000")))
