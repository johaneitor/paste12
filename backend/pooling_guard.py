from sqlalchemy import event
from sqlalchemy.exc import OperationalError, DisconnectionError

def attach_pooling(app, db):
    # engine options por config (Flask-SQLAlchemy los respeta)
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", {
        "pool_pre_ping": True,
        "pool_recycle": 280,
        "pool_size": 5,
        "max_overflow": 5,
    })
    eng = db.engine

    @event.listens_for(eng, "engine_connect")
    def ping_connection(conn, branch):
        if branch:
            return
        try:
            conn.scalar("SELECT 1")
        except Exception:
            raise DisconnectionError()

    @event.listens_for(eng, "checkout")
    def checkout(dbapi_conn, conn_rec, conn_proxy):
        # lugar para checks extras si hiciera falta
        return
