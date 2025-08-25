#!/usr/bin/env python
import os
from wsgiapp import app  # Reutiliza la misma app que en producción

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=True)
