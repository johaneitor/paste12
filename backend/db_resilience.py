from sqlalchemy import text
from sqlalchemy.exc import OperationalError
from flask import jsonify

def attach(app, db):
    @app.before_request
    def _pre_ping():
        try:
            db.session.execute(text("SELECT 1"))
        except OperationalError:
            # reciclamos conexiones rotas (SSL EOF / bad mac)
            try:
                db.session.remove()
                db.engine.dispose()
            except Exception:
                pass

    @app.errorhandler(OperationalError)
    def _db_error(e):
        try:
            db.session.remove()
            db.engine.dispose()
        finally:
            return jsonify({"ok": False, "error": "db_unavailable"}), 503
