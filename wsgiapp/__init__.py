# Bridge: siempre exporta app desde render_entry
try:
    from render_entry import app as app  # preferido: añade /api/debug-urlmap y fallback /api/notes
except Exception as _e:
    # Último recurso: intenta la app original
    try:
        from wsgi import app as app
    except Exception:
        from flask import Flask, jsonify
        app = Flask(__name__)
        @app.get("/api/health")
        def _health():
            return jsonify(ok=True, note="shim-fallback"), 200
